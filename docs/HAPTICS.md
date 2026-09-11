# Touch feedback

Riff pairs a restrained tactile language with its visual press response:

- One light impact per deliberate pad activation, including local playback and tapping again to stop. It acknowledges the tap, not successful PC playback.
- One light impact for Stop all on the board.
- Selection feedback for a different deck or theme, page arrows, and entering or leaving Play mode.
- Native pickers, sliders, and switches retain their system feedback without an extra layer.

Network responses, playback ending, Steam switching decks, and connection refreshes stay quiet. Locked desktop actions stay quiet too. Pad bounce now follows the tap rather than the network spinner and respects Reduce Motion.

## Hardware and verification

An iPad touchscreen does not provide iPhone-style vibration. SwiftUI asks the system for feedback, and unsupported requests are silently ignored. Apple documents support in some accessories, including Pencil Pro and compatible trackpads; it varies by feedback type and interaction. Riff adds no controller rumble or synthetic click audio. Visual feedback remains available.

The simulator build passes. Physical supported hardware is still required to judge tactile feel; light impacts currently request intensity 0.6. Simulator vibration was not tested or claimed.

References: [Apple’s haptic design guidance](https://developer.apple.com/design/human-interface-guidelines/playing-haptics) and [Apple’s feedback API guidance](https://developer.apple.com/documentation/applepencil/playing-haptic-feedback-in-your-app).
