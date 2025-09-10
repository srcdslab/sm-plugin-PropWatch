# Copilot Instructions for PropWatch SourceMod Plugin

## Repository Overview

This repository contains **PropWatch**, a SourcePawn plugin for SourceMod that monitors and punishes Counter-Terrorist players who inflict excessive damage on friendly props. The plugin automatically teleports and infects offending players when they exceed configurable damage thresholds.

**Key Technologies:**
- **Language**: SourcePawn (C-like scripting language for Source engine)
- **Platform**: SourceMod 1.11+ (Source engine game server modification framework)
- **Build System**: SourceKnight (SourcePawn build tool)
- **Target Games**: Counter-Strike: Source, CS:GO, other Source engine games

## Project Structure

```
addons/sourcemod/
├── scripting/
│   ├── PropWatch.sp          # Main plugin source (438 lines)
│   └── include/
│       └── PropWatch.inc     # Native forward declarations for other plugins
└── translations/
    ├── propwatch.phrases.txt # English translations
    └── ru/                   # Russian translations
```

**Configuration Files:**
- `sourceknight.yaml` - Build configuration and dependencies
- `.github/workflows/ci.yml` - CI/CD pipeline
- Plugin expects `configs/propwatch.cfg` at runtime (prop model paths)

## Language & API Specifics

### SourcePawn Language Features
- **Syntax**: C-like with strong typing
- **Memory Management**: Manual with `delete` operator (no null checks needed)
- **Arrays**: Use `ArrayList`/`StringMap` instead of native arrays
- **Strings**: Fixed-size character arrays with helper functions
- **Includes**: Use `#include` for SourceMod API and dependencies

### Critical SourceMod Patterns
```sourcepawn
// Plugin lifecycle
public void OnPluginStart() { /* initialization */ }
public void OnMapStart() { /* per-map setup */ }
public void OnMapEnd() { /* cleanup */ }

// Event handling
HookEvent("round_start", Event_RoundStart);
public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)

// Entity hooks
SDKHook(entity, SDKHook_OnTakeDamage, OnTakeDamage);
public Action OnTakeDamage(int entity, int& attacker, int& inflictor, float& damage, int& damagetype)

// ConVar usage
ConVar g_cvMaxDamage = CreateConVar("sm_propwatch_maxdmg", "2500", "Description");
g_cvMaxDamage.IntValue  // Access value
```

## Code Style & Standards

### Naming Conventions
- **Functions**: PascalCase (`TeleportPlayer`, `IsValidClient`)
- **Variables**: camelCase for locals (`int iPropDamage`)
- **Globals**: `g_` prefix (`g_iPropDamage`, `g_bRoundEnd`)
- **Arrays**: Descriptive names (`g_arPropPaths`)
- **Handles**: `g_h` prefix (`g_hHudMsg`)

### Code Formatting
- **Indentation**: 4 spaces (tabs in original)
- **Pragmas**: While `#pragma semicolon 1` and `#pragma newdecls required` are best practices for new SourcePawn code, this existing plugin doesn't use them
- **Braces**: Opening brace on same line for functions, new line for control structures

### Memory Management Rules
- **Always use `delete`** for cleanup - no null checks needed before delete
- **Prefer `delete` + recreate** over `.Clear()` for major cleanup (e.g., map changes)
- **Use `.Clear()`** for routine cleanup within same map/context
- **Pattern for major cleanup**: `delete g_arPropPaths; g_arPropPaths = new ArrayList(128);`
- **Pattern for routine cleanup**: `g_arPropPaths.Clear();`
- **Handles**: Use `delete handle` instead of `CloseHandle(handle)`

## Dependencies & Integration

### Required Dependencies (from sourceknight.yaml)
- **sourcemod**: 1.11.0-git6934+
- **multicolors**: Chat color formatting
- **zombiereloaded**: Core zombie mod integration
- **dynamicchannels**: HUD channel management (optional)
- **zr_lasermines**: Laser mine detection (optional)

### Optional Plugin Integration Pattern
```sourcepawn
// Library detection
bool g_bPluginLaserMines = false;
bool g_bNative_IsEntityLasermine = false;

public void OnAllPluginsLoaded() {
    g_bPluginLaserMines = LibraryExists("zr_lasermines");
    CheckAllNatives();
}

// Native availability checking
void CheckAllNatives() {
    if (g_bPluginLaserMines && !g_bNative_IsEntityLasermine) {
        g_bNative_IsEntityLasermine = CanTestFeatures() && 
            GetFeatureStatus(FeatureType_Native, "ZR_IsEntityLasermine") == FeatureStatus_Available;
    }
}

// Conditional compilation with tryinclude
#undef REQUIRE_PLUGIN
#tryinclude <zr_lasermines>
#define REQUIRE_PLUGIN

// Safe native usage
#if defined _zrlasermines_included
    if (g_bPluginLaserMines && g_bNative_IsEntityLasermine && ZR_IsEntityLasermine(entity))
        return Plugin_Continue;
#endif
```

## Build System

### SourceKnight Configuration
- **Build tool**: SourceKnight (declarative build system for SourceMod)
- **Config file**: `sourceknight.yaml`
- **Output**: Compiled `.smx` files in `/addons/sourcemod/plugins/`
- **Dependencies**: Auto-downloaded and extracted to include paths

### Local Development Build
```bash
# Using GitHub Action (recommended)
# Builds automatically on push/PR to main/master

# Manual build (if SourceKnight installed locally)
sourceknight build
```

### CI/CD Pipeline
- **Triggers**: Push to main/master, PRs, tags
- **Build**: Uses `maxime1907/action-sourceknight@v1`
- **Artifacts**: Creates packages with plugin and translations
- **Releases**: Auto-creates releases for tags and latest

## Configuration & Deployment

### Runtime Configuration (ConVars)
```
sm_propwatch_maxdmg 2500                    // Max friendly prop damage
sm_propwatch_nadedmgmultiplier 10           // Grenade damage multiplier
sm_propwatch_maxpropdist 200               // Max prop distance from owner
sm_propwatch_mindist_scale 0.65            // Player stuck detection scale
sm_propwatch_resetdmg 1                    // Reset damage over time
sm_propwatch_resetdmg_time 60              // Reset timeout (seconds)
sm_propwatch_hudlocation "0.8 0.5"         // HUD X Y coordinates
sm_propwatch_hudcolors "255 0 0"           // HUD RGB colors
sm_propwatch_hud_channel 4                 // Dynamic channel ID (0-5)
```

### Required Runtime Files
- `configs/propwatch.cfg` - List of prop model paths to monitor
- `translations/propwatch.phrases.txt` - Localization strings
- `logs/propwatch.cfg` - Plugin log output (auto-created)

## Key Functionality Areas

### Damage Tracking System
- **Entity Hook**: `SDKHook_OnTakeDamage` on physics props
- **Validation**: Team check (CT vs CT), distance limits, stuck detection
- **Accumulation**: Tracks cumulative damage per player
- **Reset Logic**: Time-based damage reset system

### Player Punishment Flow
1. **Teleport**: Move to spawn position + 1.5 units up
2. **Infect**: Convert CT to zombie via ZR_InfectClient()
3. **Notify**: Chat messages to player and server
4. **Log**: Write to propwatch.cfg with SteamID and map
5. **Forward**: Fire PropWatch_OnClientPunished for other plugins

### HUD Display Integration
- **Dynamic Channels**: Optional integration with DynamicChannels plugin
- **Synchronized HUD**: Falls back to standard HUD synchronizer
- **Real-time Updates**: Shows current/max damage as player shoots props

## Common Development Patterns

### Client Validation
```sourcepawn
stock bool IsValidClient(int client) {
    return (0 < client <= MaxClients && 
            IsClientInGame(client) && 
            !IsFakeClient(client) && 
            IsPlayerAlive(client));
}
```

### Safe String Operations
```sourcepawn
char sMessage[256];
FormatEx(sMessage, sizeof(sMessage), "%t", "HudText", damage, maxDamage);
```

### Translation Usage
```sourcepawn
LoadTranslations("propwatch.phrases");  // In OnPluginStart()
CPrintToChat(client, "%t", "ChatTextClient");  // Usage
```

### Event-Driven Architecture
- Hook game events (`round_start`, `player_spawn`, etc.)
- Use `RequestFrame()` for delayed execution
- Implement proper cleanup in round/map transitions

## Testing & Validation

### Manual Testing Approach
1. **Server Setup**: Deploy on CS:S/CS:GO test server with ZombieReloaded
2. **Prop Testing**: Spawn props, shoot as CT, verify damage tracking
3. **Threshold Testing**: Exceed damage limit, verify teleport/infection
4. **Integration Testing**: Test with/without optional plugins
5. **Map Transitions**: Verify cleanup and reset behavior

### Common Issues to Check
- **Memory Leaks**: Ensure ArrayList/StringMap properly deleted and recreated
- **Invalid Clients**: Always validate client indices and states
- **Plugin Dependencies**: Handle missing optional plugins gracefully
- **SQL Injection**: Escape all user input in database operations
- **Performance**: Minimize operations in frequently called hooks

### Debug Output
```sourcepawn
PrintToServer("[PropWatch] Debug: %s", message);  // Console output
LogToFile(g_sLogFile, "[PropWatch] %s", message); // File logging
```

## Performance Considerations

### Optimization Guidelines
- **Minimize SDKHook usage**: Only hook entities that need monitoring
- **Cache expensive operations**: Store frequently accessed values
- **Avoid O(n) operations**: Use hash maps instead of linear searches
- **Limit string operations**: Minimize formatting in hot paths
- **Timer usage**: Prefer event-driven over polling with timers

### Critical Performance Areas
- `OnTakeDamage` hook (called frequently during combat)
- Entity tracing for stuck detection
- Client validation loops
- HUD updates (limit frequency)

## Error Handling

### SourceMod Error Patterns
```sourcepawn
// File operations
if (!FileExists(FilePath)) {
    PrintToServer("[PropWatch] Missing file %s", FilePath);
    return;
}

// Client operations
if (!IsValidClient(client)) {
    return;
}

// Entity validation
if (!IsValidEntity(entity)) {
    return;
}
```

## Documentation Standards

- **No excessive headers**: Avoid unnecessary comments in plugin files
- **Native documentation**: Document all public natives in .inc files
- **Parameter documentation**: Include types, descriptions, return values
- **Complex logic**: Comment non-obvious algorithms and calculations
- **Translation keys**: Document all phrase keys and format parameters

This plugin integrates deeply with the SourceMod ecosystem and requires understanding of Source engine entity systems, game events, and the specific patterns used in competitive CS:S/CS:GO zombie modification servers.