# Vesc to Ninebot Dashboard interface

Lisp code to use a Ninebot dashboard (either G30 or ES2/ES4 based) on a VESC(tm) based controller. (*requires VESC Firmware 6 or above*)

## Wiring

Ninebot dashboards use a half-duplex serial link. To connect the dashboard to your VESC you should wire the **YELLOW** wire from the dashboard to the **TX** pin of the VESC uart connector.

Currently the button is not supported but for future reference the button uses the **GREEN** wire from the dashboard, it should be connected to an input on the VESC with a pullup resistor in place, when the button is pressed it grounds the line.

### A note on wiring

When I was first wiring up the dashboard I didn't want to cut the wire from the dashboard. I bought a wire from Amazon that had a Julet (or Higo) connector on one side and 4 loose wires on the other. While wiring it up I discovered the pin/colors were not wired to the same pins at the Julet connector. i.e. the ground wire correctly passed through to the ground wire on the dashboard, but the other three wires were swapped in the connector. After a little investigation it seems this is a common problem as there is no specification for pin to wire color only connector size and pin spacing.

I **strongly** recommend you test continuity all the way from the soldered connector on the dashboard through to the end of the wire you intend to interface to the VESC.  You might find that the +5v is the green wire, or alternatively you may receive a connector wire that has red/black/blue/white wires instead.

The only way to properly deal with this is to talk about colors from the dashboard side of things. On an ES2/ES4 dashboard looking at it from the circuit board side the colors and pins should be

```
[red]  [green]  [yellow]  [black]

5v     button   uart      ground
```
## Software

The script currently listens for commands `0x64` and `0x65` that come from the dashboard, the dashboard sends these packets with a data blob that includes the levels of the hall sensors for both throttle and brake, these packets are decoded (*but not currently used as of now*). The intention is to process this data and convert them to `(set-current-rel)` and `(set-brake-rel)` commands.

When a `0x64` packet is received the dashboard expects a reply, the packet contains data that sets the info the dashboard should display, including a bit-field that sets particular properties to display.

#### on an ES2/ES4 dashboard
Right now, the bitfield is configured to hide the (S) (the (S) is used to show either Sport mode (in red) or Eco mode (in blue)) and switch the speed display to `mph`

#### on a G30 Max dashboard
The Bitfield is configured to show the (D) option for 'drive' mode and switch the speed display to `mph`

#### general display
The speed is currently calculated and displayed as MPH, VESC provides the details as meters/sec. Eventually there should be an option to allow display as either km/h or miles/h

Battery level is read from the vesc and displayed on the dashboard. The Ninebot dashboard battery display has 5 segments, a solid segment represents 11-20% of charge and a flashing segment represents 0-10% of charge, adding up the segments gives an estimation of charge state

e.g. 3 solid segments, a flashing segment, and an empty segment would be `(20+20+20)+(10)+(0) = 60-70%` charge
