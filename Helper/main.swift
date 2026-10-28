// FM-SWITCH's flash tool: reads and writes an FM-1's flash in the chip's download mode, for the
// app.
//
// The app starts it as root with the person's administrator password, as a child of the app,
// and talks to it over the pipe that's the tool's standard input and output. It does what it's
// asked one step at a time, and quits when the app lets go.

import Foundation

FlashToolSession(line: FlashLine.standard()).run()
