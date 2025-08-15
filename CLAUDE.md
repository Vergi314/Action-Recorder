# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an Action Recorder addon for Garry's Mod that allows players to record and playback movements of props. The addon consists of two main components:

1. **Action Recorder Tool** - Records prop movements and creates playback boxes
2. **Action Playback Box Entity** - Plays back recorded movements with various loop modes and easing functions

## Architecture

### Core Components

- `lua/weapons/gmod_tool/stools/actionrecorder.lua` - Main tool implementation
- `lua/entities/action_playback_box.lua` - Playback entity with timer-based animation system
- `lua/autorun/ar_constants.lua` - Global constants and enums
- `lua/autorun/action_recorder_easing.lua` - Easing function library
- `lua/autorun/1_action_recorder_logging.lua` - Debug logging system
- `lua/autorun/action_recorder_cl_options.lua` - Client-side ConVar definitions
- `lua/vgui/action_recorder_graph_editor.lua` - Custom easing curve editor UI

### Key Architecture Patterns

The addon uses a **global timer system** where all playback boxes share a single timer (`ActionRecorder_GlobalPlayback`) with 50Hz update rate (0.02s interval). This is currently being refactored to support multiple independent timers for better performance.

**Data Flow:**
1. Tool records prop data into `Player.ActionRecordData` table
2. Playback box receives this data on creation
3. Global timer processes all active boxes every frame
4. Each box interpolates between recorded keyframes using easing functions

### Constants and Enums

Key constants are defined in `ar_constants.lua`:
- `AR_LOOP_MODE` - Playback loop types (NO_LOOP, LOOP, PING_PONG, NO_LOOP_SMOOTH)
- `AR_PLAYBACK_DIRECTION` - Forward/reverse playback
- `AR_PLAYBACK_TYPE` - Absolute vs relative positioning
- `AR_ANIMATION_STATUS` - Animation state tracking
- `AR_FRAME_INTERVAL` - Global timer interval (0.02s)

## Development Workflow

### No Build System
This addon has no build process - Lua files are loaded directly by Garry's Mod. Simply modify files and restart the game or use `lua_openscript_cl/sv` console commands for hot reloading.

### Development Setup
The project includes EmmyLua configuration (`.emmyrc.json`) for IDE support with:
- Disabled `undefined-global` diagnostics (GMod globals are not recognized)
- Latest Lua version support
- Enhanced completion and diagnostics

### Testing
No automated test framework is present. Testing is done in-game by:
1. Loading the addon in GMod
2. Using the Action Recorder tool in sandbox mode
3. Recording prop movements and testing playback with different settings

### Debugging
Use the `ARLog()` function for debug output, controlled by the `ar_debug` ConVar. Enable with `ar_debug 1` in console.

## Code Conventions

### File Organization
- Tools go in `lua/weapons/gmod_tool/stools/`
- Entities in `lua/entities/`
- Shared initialization code in `lua/autorun/`
- Client-specific autorun files use `_cl` suffix
- Server-specific code uses `SERVER` conditional blocks

### GMod-Specific Patterns
- Use `AddCSLuaFile()` at the top of shared files
- Separate CLIENT/SERVER code blocks with conditionals
- Network strings must be registered on SERVER with `util.AddNetworkString()`
- ConVars use FCVAR_REPLICATED for server-client synchronization
- Entity networking uses `SetNW*()` functions

### Naming Conventions
- Constants use SCREAMING_SNAKE_CASE
- Functions use PascalCase for GMod hooks, camelCase for helpers
- Global tables use PascalCase (e.g., `ActionRecorder.EasingFunctions`)
- Network message names prefixed with addon name

## Important Implementation Details

### Global Timer System
All active playback boxes are managed by a single global timer. The system maintains:
- `ActivePlaybackBoxes` table tracking all playing entities
- Single timer callback processing all boxes each frame
- Automatic cleanup when boxes are removed

### Easing System
Comprehensive easing function library with:
- Standard easing types (Linear, Sine, Quad, Cubic, etc.)
- Custom amplitude, frequency, and offset parameters
- Inversion support for reversed easing curves
- Interactive graph editor for creating custom easing curves via VGUI panel

### Wiremod Integration
Playback boxes support Wiremod with:
- Inputs: Play, Stop, PlaybackSpeed, LoopMode
- Outputs: IsPlaying, PlaybackSpeed, Frame
- Conditional loading based on WireLib presence

### ConVar System
Extensive configuration through ConVars:
- Server ConVars with FCVAR_REPLICATED for global settings
- Client ConVars for per-player preferences (HUD, sounds, film grain, physics teleport)
- Settings persist between sessions with FCVAR_ARCHIVE

## Current Known Issues

Based on recent commits and documentation:
1. **Performance Issues**: Single global timer causes performance problems with many playback boxes
2. **Entity Control Conflicts**: Props can only be controlled by one box at a time
3. **Speed Issues**: Playback speeds lower than 1.0 have known bugs
4. **Multiple Entity Support**: Work in progress to support multiple entities per recording

## Network Architecture

The addon uses several network messages:
- `ActionRecorder_PlayStartSound` - Start recording audio cues
- `ActionRecorder_PlayLoopSound` - Loop playback audio
- `ActionRecorder_StopLoopSound` - Stop audio loops
- `ActionRecorderNotify` - General notifications
- `ActionRecorder_FlashEffect` - Visual recording effects