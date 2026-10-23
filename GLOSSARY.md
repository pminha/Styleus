# Styleus

Styleus turns an iPad and Apple Pencil into a pointing and drawing surface for a paired Mac.

## Language

**Trackpad mode**:
A mode in which Pencil movement changes the Mac cursor relative to its current position. Stationary taps produce clicks; lifting after movement and repositioning do not jump the cursor or click.
_Avoid_: Absolute mode, tablet mode

**Drawing-tablet mode**:
A mode in which each location in the active drawing area corresponds to a fixed location in a target region on the Mac.
_Avoid_: Trackpad mode, pressure support

**Basic drawing**:
Drawing in which pressure-activated Pencil contact produces an ordinary mouse stroke on the Mac. This does not imply that a drawing application receives pressure or tilt values.
_Avoid_: Pressure-sensitive drawing, universal tablet support

**Pressure-sensitive drawing**:
Drawing in which the Mac drawing application receives and uses changing Pencil pressure during a stroke.
_Avoid_: Pressure capture, basic drawing

**Active drawing area**:
The part of the iPad surface whose locations correspond to the selected Mac target region.
_Avoid_: Entire screen, canvas

**Target region**:
The selected rectangular area of a Mac display to which the active drawing area maps. A target region may occupy the whole display.
_Avoid_: iPad drawing area, canvas

**Stroke**:
A continuous drawing mark beginning when Pencil pressure reaches the activation threshold and ending when pressure eases, the Pencil lifts, or input is interrupted.
_Avoid_: Session, connection

**Pairing**:
An explicitly approved trust relationship between an iPad and a Mac that permits the iPad to control that Mac.
_Avoid_: Discovery, connection

**Connection**:
An active communication link between the paired devices.
_Avoid_: Pairing

**Connection choice**:
The user's selection of wired or Wi-Fi communication. Changing this choice ends the current connection and requires an explicit reconnect.
_Avoid_: Pairing, automatic fallback

**Pressure drag**:
A trackpad drag that holds the primary mouse button while the Pencil moves with sufficient pressure. Easing pressure, lifting, or an interruption releases it.
_Avoid_: Drag Lock, right-button drag

**Pressure activation**:
Using Pencil pressure to decide when a mouse drag or drawing stroke begins and ends. It does not imply pressure-dependent ink width in the receiving Mac app.
_Avoid_: Pressure-sensitive drawing, tablet compatibility

**Inactive margin**:
The portion of the iPad movement surface outside the active drawing area when their aspect ratios differ.
_Avoid_: Drawing area, cropped canvas

**Pencil input**:
A pointing interaction in which Apple Pencil controls cursor movement, clicks, and drawing. Fingers do not move or click the pointer.
_Avoid_: Finger input, pressure-sensitive input

**Two-finger scrolling**:
Sliding two fingers together on the main surface to scroll the Mac content vertically or horizontally. Pencil contact takes priority over scrolling.
_Avoid_: Finger pointer movement, separate Scroll area
