;UART configuration on the COMM port
(uart-start 115200 'half-duplex) ;uses only the tx pin
;(gpio-configure 'pin-rx 'pin-mode-in-pu) ;configures rx pin for button presses

;Pre-defined fields for uart output
;Ninebot protocol:
; uwHeader bLen bSrcAddr bDstAddr bCmd bArg bPayload[bLen] wChecksumLE
; 0-1      2    3        4        5    6    bLen (0-256)

; Source and Destination defines
; 0x00 - Broadcast to everything on the bus
; 0x20 - Master control of electric scooter (ESC)
; 0x21 - Bluetooth instrument (i.e. Dashboard)
; 0x22 - Built-in battery of ES
; 0x23 - External battery of ES
; 0x3D - PC upper computer connected through serialport / CAN debugger/IoT equipment
; 0x3E - Mobile phone linked through Bluetooth serial port (BLE)

; If bCmd is 64 then the dash is asking for a data update
; If bCmd is 65 then the dash is sending us the throttle and brake hall sensor values

; Buffer for storing the header from the serial port
; since this is byte aligned we should read one byte at a time
; putting it in header-buf[1], then we compare header-buf to 0x5AA5,
; if neq then we copy header-buf[1] into header-buf[0] and loop
(define header-buf (array-create type-byte 3))
(bufset-u16 header-buf 0 0x0000)

; 5 bytes for the info part of the packet (bLen to bArg)
(define info-buf (array-create type-byte 6))
(define bLen 0)
(define bSrcAddr 0)
(define bDstAddr 0)
(define bCmd 0)
(define bArg 0)

; Buffer for data incoming bytes from uart
(define data-buf (array-create type-byte 256))

(define crc-buf (array-create type-byte 3))
(define wChecksumLE 0)


;throttle low high range 0 - 157
(define fThrottleLowLevel 40.0)
(define fThrottleHighLevel (- 197.0 fThrottleLowLevel))

;brake low high range 0 - 140
(define fBrakeLowLevel 41.0)
(define fBrakeHighLevel (- 181.0 fBrakeLowLevel))

(define bShowMPH 0)

(defun send-dash-update () ;Dash wants information update, 0x64 command
    (progn
        (define tx-frame (array-create 15))
        (bufset-u16 tx-frame 0 0x5AA5) ;Ninebot protocol
        (bufset-u8 tx-frame 2 0x06) ;Payload length is 6 bytes
        (bufset-u8 tx-frame 3 0x20) ;Source = 20 (ESC)
        (bufset-u8 tx-frame 4 0x21) ;Destination = 21 (Dashboard)
        (bufset-u8 tx-frame 5 0x64) ;Command (64 in this case)
        (bufset-u8 tx-frame 6 0x00) ;Arg

        ;bFlags field
        ;bit, value
        ;0    1  = drive
        ;1    2  = eco
        ;2    4  = sport
        ;3    8  = charge
        ;4    16 = off
        ;5    32 = lock
        ;6    64 = 0=show kph / 1 = show mph
        ;7   128 = Overheating flag (flashes red thermometer) 
        (setvar 'speed-mode 4)
        (setvar 'mph-flag (* 64 bShowMPH))
        (bufset-u8 tx-frame 7 (bitwise-or speed-mode mph-flag))

        ;bBattLevel - 0-100 for NB, 0.0-1.0 from vesc
        (bufset-u8 tx-frame 8 (* (get-batt) 100))

        ;bHeadlightLevel - lamp status
        (bufset-u8 tx-frame 9 0)

        ;bBeeps - beeper
        (bufset-u8 tx-frame 10 0)

        ;bSpeed - current speed, 0.1 kmh units
        ; to convert vesc (meters/sec) to ninebot (mph)
        (if (= bShowMPH 1)
            (setvar 'speed (to-i32 (* (get-speed) 2.237) ))
            (setvar 'speed (to-i32 (* (get-speed) 3.6) )))
        
        (bufset-u8 tx-frame 11 speed)

        ;bErrorCode - error codes
        (bufset-u8 tx-frame 12 0)

        ;wChecksumLE = 0xFFFF xor (16-bit sum of bytes <bLen bSrcAddr bDstAddr bCmd bArg bPayload[]>)
        (setvar 'crcout 0)
        (looprange i 2 13
            (setvar 'crcout (+ crcout (bufget-u8 tx-frame i)))
        )
        (setvar 'crcout (bitwise-xor crcout 0xFFFF))

        (bufset-u8 tx-frame 13 crcout)
        (bufset-u8 tx-frame 14 (shr crcout 8))

        (uart-write tx-frame)
    )
)

(defun process_hall_update (data datalen)
    (progn        
        ; data looks like:
        ; <bDataLen> <bThrottleLevel> <bBrakeLevel> <bIsUpdatingBLEFW> <bIsBeeping>
        ; bThrottleLevel goes from 0x28 to 0xC5 (40 to 197)
        ; bBrakeLevel goes from 0x29 to 0xB5 (41 to 181)
        ; bIsUpdating is 0 or 1
        ; bIsBeeping is 0 or 1

        (setvar 'fThrottle (to-float (bufget-u8 data 1)))
        (setvar 'fThrottleRel (/ (- fThrottle fThrottleLowLevel) fThrottleHighLevel))
        (if (> fThrottleRel 0.002)
            (set-current-rel fThrottleRel)
            (set-current-rel 0)
        )

        (setvar 'fBrake (to-float (bufget-u8 data 2)))
        (setvar 'fBrakeRel (/ (- fBrake fBrakeLowLevel) fBrakeHighLevel))
        (if (> fBrakeRel 0.002)
            (set-brake-rel fBrakeRel)
        )
    )
)

; Given an array of bytes holding the info and an array holding the data
(defun calc-crc (info data datalen)
    (progn
        (setvar 'icrc 0)

        ;prepare checksum, add values of bLen bSrcAddr bDstAddr bCmd bArg bPayload
        (looprange i 0 4
            (setvar 'icrc (+ icrc (bufget-u8 info i)))
            (setvar 'icrc (bitwise-xor crc 0xFFFF))
        )

        ;add values of the databuffer to the crc mix
        (looprange j 0 datalen
            (setvar 'icrc (+ icrc (bufget-u8 data j)))
            (setvar 'icrc (bitwise-xor crc 0xFFFF))
        )

        ;do 0xFFFF xor (16-bit sum of bytes <bLen bSrcAddr bDstAddr bCmd bArg bPayload[]>)
        (bitwise-and
            (+ (shr (bitwise-xor icrc 0xFFFF) 8)
            (shl (bitwise-xor icrc 0xFFFF) 8))
        0xFFFF)
    )
)

(loopwhile t
    (progn
        ; read a single byte from the uart into the top byte of the header-buf
        ; this is fine because this byte will move down to lower byte
        ; this way we basically create a sliding window over the incoming serial data
        (uart-read-bytes header-buf 1 1)

        ;Is this a Ninebot Protocol header?
        (if (= (bufget-u16 header-buf 0) 0x5AA5)
            (progn
                ; next we need to read 5 bytes into the info field
                (uart-read-bytes info-buf 5 0)

                ; decode the info-buf into variables
                (setvar 'bLen (bufget-u8 info-buf 0))
                (setvar 'bSrcAddr (bufget-u8 info-buf 1))
                (setvar 'bDstAddr (bufget-u8 info-buf 2))
                (setvar 'bCmd (bufget-u8 info-buf 3))
                (setvar 'bArg (bufget-u8 info-buf 4))

                ; read bLen bytes from the uart (this is the data)
                (uart-read-bytes data-buf bLen 0)

                ; finally read the CRC
                (uart-read-bytes crc-buf 2 0)

                ; TODO Calculate CRC
                (define crc (bufget-u16 crc-buf 0))

                (define ccrc (calc-crc info-buf data-buf bLen))

                (if (= crc ccrc)
                    (progn
                        (if(= bCmd 0x64)
                            ; Command 0x64 is a request from the Dashboard for
                            ; a Status update, it also includes the current
                            ; Throttle/Hall sensor data (like 0x65)
                            ;(print "Command: 0x64")
                            (send-dash-update)
                            (process_hall_update data-buf bLen)
                        )

                        (if(= bCmd 0x65)
                            ; Command 0x65 is a Throttle/Hall sensor update
                            ; This command does not expect a reply
                            ;(print "Command: 0x65")
                            (send-dash-update)
                            (process_hall_update data-buf bLen)
                        )
                    )
                )
            )

            ; Reset the CRC
            (setvar 'wChecksumLE 0)
            (bufset-u16 crc-buf 0 0x0000)

            ; finally reset the header so we dont false-positive
            (bufset-u16 header-buf 0 0x0000)            
        )

        (bufset-u8 header-buf 0 (bufget-u8 header-buf 1)) ;copy header-buf[1] to header-buf[0]
    )
)
