#!/bin/bash
# Virtual display sized to the phone screen plus room for the emulator's side toolbar.
exec Xvfb :0 -screen 0 "$((PHONE_WIDTH + TOOLBAR_WIDTH))x${PHONE_HEIGHT}x24" -nolisten tcp
