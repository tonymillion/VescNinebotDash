# Vesc to Ninebot Dashboard interface

Lisp code to use a Ninebot dashboard (either G30 or ES2/ES4 based) on a VESC(tm) based controller. (*requires VESC Firmware 6 or above*)

## Wiring

Ninebot dashboards use a half-duplex serial link. To connect the dashboard to your VESC you should wire the **YELLOW** wire from the dashboard to the **TX** pin of the VESC uart connector.

Currently the button is not supported but for future reference the button uses the **GREEN** wire from the dashboard, it should be connected to an input on the VESC with a pullup resistor in place, when the button is pressed it grounds the line.

## Software

The script currently listens for commands 0x64 and 0x65 that come from the dashboard, the dashboard sends these packets with a data blob that includes the levels of the hall sensors for both throttle and brake, these packets are decoded (*but not currently used as of now*). The intention is to process this data and convert them to `(set-current-rel)` and `(set-brake-rel)` commands.

When a 0x64 packet is received the dashboard expects a reply, the packet contains data that sets the info the dashboard should display, including a bit-field that sets particular properties to display.

### on an ES2/ES4 dashboard
Right now, the bitfield is configured to hide the (S) (to show either Sport (in red) or Eco (in blue) and switch the speed display to MPH

### on a G30 Max dashboard
The Bitfield is configured to show the (D) option for 'drive' mode and switch the speed display to MPH

#### general display
The speed is currently calculated and displayed as MPH, VESC provides the details as meters/sec. Eventually there should be an option to allow display as either km/h or miles/h

Battery level is read from the vesc and displayed on the dashboard. The Ninebot dashboard battery display has 5 segments, a solid segment represents 11-20% of charge and a flashing segment represents 0-10% of charge, adding up the segments gives an estimation of charge state

e.g. 3 solid segments, a flashing segment, and an empty segment would be (20+20+20)+(10)+(0) = 60-70% charge
