#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <multicolors>
#include <zombiereloaded>

#undef REQUIRE_PLUGIN
#tryinclude <zr_lasermines>
#tryinclude <DynamicChannels>
#define REQUIRE_PLUGIN

ConVar g_cvMaxPropDamage, g_cvNadeDamageMultiplier;
ConVar g_cvMaxPropDistance, g_cvMinPropDistance;
ConVar g_cvResetPropDamage, g_cvResetPropDamageTime;
ConVar g_cvHudLocation, g_cvHudColors, g_cvHUDChannel;

Handle g_hHudMsg = INVALID_HANDLE;

int g_iPropDamage[MAXPLAYERS+1]
	, g_iLastPropShotTime[MAXPLAYERS+1]
	, g_iHudColor[3];

float fPosition[MAXPLAYERS+1][3]
	, fHudLocation[2];

bool g_bRoundEnd = false
	, g_bBlockDamage[MAXPLAYERS+1] = { false, ... }
	, g_bZMSpawned = false
	, g_bPluginLaserMines = false
	, g_bPluginDynamicChannels = false
	, g_bNative_IsEntityLasermine = false
	, g_bNative_GetDynamicChannel = false;

char g_sMapName[PLATFORM_MAX_PATH]
	, g_sLogFile[PLATFORM_MAX_PATH];

ArrayList g_arPropPaths;

public Plugin myinfo =
{
	name = "PropWatch",
	author = "ire.",
	description = "Automatically teleport and infect players who shoot props of their teammates",
	version = "1.7.0"
};

public void OnPluginStart()
{
	LoadTranslations("propwatch.phrases");

	g_cvMaxPropDamage = CreateConVar("sm_propwatch_maxdmg", "2500", "The amount of damage a player can do to friendly props");
	g_cvNadeDamageMultiplier = CreateConVar("sm_propwatch_nadedmgmultiplier", "10", "The damage multiplier to apply when using a grenade against friendly props");
	g_cvMaxPropDistance = CreateConVar("sm_propwatch_maxpropdist", "200", "Only include props that are within this radius (units) from the owner");
	g_cvMinPropDistance = CreateConVar("sm_propwatch_mindist_scale", "0.65", "Multiplier to scale the player model to check if the player is stuck in a prop [1 = fully stuck 0.5 = half stuck]");
	g_cvResetPropDamage = CreateConVar("sm_propwatch_resetdmg", "1", "Reset dealt prop damage after a certain period of time if the player has not shot friendly props during that [0 = no 1 = yes]");
	g_cvResetPropDamageTime = CreateConVar("sm_propwatch_resetdmg_time", "60", "The amount of seconds before resetting dealt prop damage");
	g_cvHudLocation = CreateConVar("sm_propwatch_hudlocation", "0.8 0.5", "X and Y coordinates of the HUD text");
	g_cvHudColors = CreateConVar("sm_propwatch_hudcolors", "255 0 0", "RGB color values of the HUD text");
	g_cvHUDChannel = CreateConVar("sm_propwatch_hud_channel", "4", "The channel for the hud if using DynamicChannels", _, true, 0.0, true, 6.0);

	HookConVarChange(g_cvHudLocation, OnConVarChanged);
	HookConVarChange(g_cvHudColors, OnConVarChanged);

	AutoExecConfig();

	BuildPath(Path_SM, g_sLogFile, sizeof(g_sLogFile), "logs/propwatch.cfg");

	g_arPropPaths = new ArrayList(128);
	g_hHudMsg = CreateHudSynchronizer();

	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_spawn", Event_PlayerSpawn);
}

public void OnAllPluginsLoaded()
{
	g_bPluginLaserMines = LibraryExists("zr_lasermines");
	g_bPluginDynamicChannels = LibraryExists("DynamicChannels");

	CheckAllNatives();
}

public void OnLibraryAdded(const char[] name)
{
	if (strcmp(name, "zr_lasermines", false) == 0)
		g_bPluginLaserMines = true;
	if (strcmp(name, "DynamicChannels", false) == 0)
		g_bPluginDynamicChannels = true;

	CheckAllNatives();
}

public void OnLibraryRemoved(const char[] name)
{
	if (strcmp(name, "zr_lasermines", false) == 0)
		g_bPluginLaserMines = false;
	if (strcmp(name, "DynamicChannels", false) == 0)
		g_bPluginDynamicChannels = false;

	CheckAllNatives();
}

public void OnMapStart()
{
	GetCurrentMap(g_sMapName, sizeof(g_sMapName));
	SetupProps();
	SetupHud();
}

public void OnMapEnd()
{
	// .Clear() is creating a memory leak
	// g_arPropPaths.Clear();
	delete g_arPropPaths;
	g_arPropPaths = new ArrayList(128);
}

void SetupProps()
{
	char FilePath[128];
	BuildPath(Path_SM, FilePath, sizeof(FilePath), "configs/propwatch.cfg");

	if(!FileExists(FilePath))
	{
		PrintToServer("[PropWatch] Missing file %s", FilePath);
		return;
	}

	g_arPropPaths.Clear();

	File file = OpenFile(FilePath, "r");
	char Line[128];
	while(!IsEndOfFile(file) && ReadFileLine(file, Line, sizeof(Line)))
	{
		TrimString(Line);
		g_arPropPaths.PushString(Line);
	}

	delete file;
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	SetupHud();
}

public void OnClientConnected(int client)
{
	ResetClientVariables(client);
}

public void OnEntityCreated(int entity, const char[] classname)
{
    SDKHook(entity, SDKHook_SpawnPost, OnSpawnPost);
}

public Action ZR_OnClientInfect(int &client, int &attacker, bool &motherInfect, bool &respawnOverride, bool &respawn)
{
	g_bZMSpawned = true;
	return Plugin_Continue;
}

stock void OnSpawnPost(int entity)
{
	char ClassName[64], PropModel[128];
	GetEntityClassname(entity, ClassName, sizeof(ClassName));
	GetEntPropString(entity, Prop_Data, "m_ModelName", PropModel, sizeof(PropModel));

	if (g_arPropPaths.FindString(PropModel) != -1 && strncmp(ClassName, "prop_physics", 11, false) == 0)
		SDKHook(entity, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action OnTakeDamage(int entity, int& attacker, int& inflictor, float& damage, int& damagetype)
{	
	if(g_bRoundEnd || !IsValidClient(attacker))
		return Plugin_Continue;

#if defined _zrlasermines_included
	if (g_bPluginLaserMines && g_bNative_IsEntityLasermine && ZR_IsEntityLasermine(entity))
		return Plugin_Continue;
#endif

	if(g_bBlockDamage[attacker])
		return Plugin_Handled;

	int g_iOwner = GetEntPropEnt(entity, Prop_Send, "m_PredictableID");

	if(!(attacker != g_iOwner && g_iOwner > 0 && GetClientTeam(attacker) == CS_TEAM_CT && GetClientTeam(g_iOwner) == CS_TEAM_CT))
		return Plugin_Continue;

	float fOwnerOrigin[3], fPropOrigin[3];
	GetEntPropVector(g_iOwner, Prop_Data, "m_vecOrigin", fOwnerOrigin);
	GetEntPropVector(entity, Prop_Data, "m_vecOrigin", fPropOrigin);

	if(GetVectorDistance(fOwnerOrigin, fPropOrigin) > g_cvMaxPropDistance.IntValue)
		return Plugin_Continue;

	if(IsAttackerStuckInProp(attacker) || IsZombieInAttackersAim(attacker))
		return Plugin_Continue;

	int iRoundedDamage = RoundToZero(damage);
	(damagetype == DMG_BLAST) ? (g_iPropDamage[attacker] += iRoundedDamage * g_cvNadeDamageMultiplier.IntValue) : (g_iPropDamage[attacker] += iRoundedDamage)

	if(g_cvResetPropDamage.BoolValue)
	{
		if(GetTime() > g_iLastPropShotTime[attacker] + g_cvResetPropDamageTime.IntValue)
			g_iPropDamage[attacker] = 0;

		g_iLastPropShotTime[attacker] = GetTime();
	}

	if(g_iPropDamage[attacker] <= g_cvMaxPropDamage.IntValue)
	{
		char sMessage[256];
		FormatEx(sMessage, sizeof(sMessage), "%t", "HudText", g_iPropDamage[attacker], g_cvMaxPropDamage.IntValue);

		int iHUDChannel = -1;
		int iChannel = g_cvHUDChannel.IntValue;

		if (iChannel < 0 || iChannel > 6)
			iChannel = 4;

	#if defined _DynamicChannels_included_
		if (g_bPluginDynamicChannels && g_bNative_GetDynamicChannel)
			iHUDChannel = GetDynamicChannel(iChannel);
	#endif

		SetHudTextParams(fHudLocation[0], fHudLocation[1], 1.0, g_iHudColor[0], g_iHudColor[1], g_iHudColor[2], 255);

		if (g_bPluginDynamicChannels)
			ShowHudText(attacker, iHUDChannel, "%s", sMessage);
		else
		{
			ClearSyncHud(attacker, g_hHudMsg);
			ShowSyncHudText(attacker, g_hHudMsg, "%s", sMessage);
		}
	}

	if(g_iPropDamage[attacker] >= g_cvMaxPropDamage.IntValue)
	{
		g_bBlockDamage[attacker] = true;
		TeleportPlayer(attacker);
	}

	return Plugin_Continue;
}

stock void TeleportPlayer(int attacker)
{
	float fAngles[3];
	GetClientEyeAngles(attacker, fAngles);
	fAngles[2] = 0.0;
	fPosition[attacker][2] += 1.5;
	TeleportEntity(attacker, fPosition[attacker], fAngles, NULL_VECTOR);

	RequestFrame(InfectClient, GetClientUserId(attacker));
}

stock void InfectClient(int userid)
{
	int client = GetClientOfUserId(userid);
	if(!client)
		return;

	ResetClientVariables(client);

	if(g_bZMSpawned && IsPlayerAlive(client) && GetClientTeam(client) == CS_TEAM_CT)
	{
		char SteamID[32];
		if (!GetClientAuthId(client, AuthId_Steam2, SteamID, sizeof(SteamID), false))
			FormatEx(SteamID, sizeof(SteamID), "Unknown");
		LogToFile(g_sLogFile, "[PropWatch] %N (%s) was punished for shooting props in %s.", client, SteamID, g_sMapName);

		// Todo in the future: API Forward + Increase client counter punishement history
		ZR_InfectClient(client);
		CPrintToChat(client, "%t", "ChatTextClient");
		CPrintToChatAll("%t", "ChatTextAll", client, SteamID);
	}
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i))
			ResetClientVariables(i);
	}

	g_bZMSpawned = false;
	g_bRoundEnd = false;
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	g_bRoundEnd = true;
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(IsClientInGame(client) && !IsFakeClient(client))
		ResetClientVariables(client);
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	RequestFrame(SaveSpawnPoint, client);
}

stock void SaveSpawnPoint(int client)
{
	int iTeam = GetClientTeam(client);

	if(IsValidClient(client) && (iTeam == CS_TEAM_T || iTeam == CS_TEAM_CT))
		GetEntPropVector(client, Prop_Send, "m_vecOrigin", fPosition[client]);
}

stock void ResetClientVariables(int client)
{
	g_iPropDamage[client] = 0;
	g_bBlockDamage[client] = false;
}

stock void SetupHud()
{
	char Location[16], Colors[16], LocationBuffer[2][8], ColorBuffer[3][4];
	g_cvHudLocation.GetString(Location, sizeof(Location));
	g_cvHudColors.GetString(Colors, sizeof(Colors));

	ExplodeString(Location, " ", LocationBuffer, sizeof(LocationBuffer), sizeof(LocationBuffer[]));
	ExplodeString(Colors, " ", ColorBuffer, sizeof(ColorBuffer), sizeof(ColorBuffer[]));

	fHudLocation[0] = StringToFloat(LocationBuffer[0]);
	fHudLocation[1] = StringToFloat(LocationBuffer[1]);

	g_iHudColor[0] = StringToInt(ColorBuffer[0]);
	g_iHudColor[1] = StringToInt(ColorBuffer[1]);
	g_iHudColor[2] = StringToInt(ColorBuffer[2]);
}

stock void CheckAllNatives()
{
	// Robust logic to check if the native is available and prevent over-check when Library is added/removed
	if (g_bPluginLaserMines && !g_bNative_IsEntityLasermine || !g_bPluginLaserMines && g_bNative_IsEntityLasermine)
		g_bNative_IsEntityLasermine = g_bPluginLaserMines && CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "ZR_IsEntityLasermine") == FeatureStatus_Available;

	if (g_bPluginDynamicChannels && !g_bNative_GetDynamicChannel || !g_bPluginDynamicChannels && g_bNative_GetDynamicChannel)
		g_bNative_GetDynamicChannel = g_bPluginDynamicChannels && CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "GetDynamicChannel") == FeatureStatus_Available;
}

stock bool IsValidClient(int client)
{
	return(0 < client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client) && IsPlayerAlive(client));
}

stock bool IsAttackerStuckInProp(int client)
{
	float fOrigin[3], fMinBounds[3], fMaxBounds[3];

	GetClientMins(client, fMinBounds);
	GetClientMaxs(client, fMaxBounds);
	GetClientAbsOrigin(client, fOrigin);

	ScaleVector(fMinBounds, g_cvMinPropDistance.FloatValue);
	ScaleVector(fMaxBounds, g_cvMinPropDistance.FloatValue);

	TR_TraceHullFilter(fOrigin, fOrigin, fMinBounds, fMaxBounds, MASK_PLAYERSOLID, TraceFilter);

	return TR_DidHit();
}

stock bool TraceFilter(int entity, int contentsMask)
{
	// Ignore clients
	if (entity > MaxClients)
		return true;

	// Ignore lasermines
#if defined _zrlasermines_included
	if (g_bPluginLaserMines && g_bNative_IsEntityLasermine && !ZR_IsEntityLasermine(entity))
		return true;
#endif

	return false;
}

stock bool IsZombieInAttackersAim(int client)
{
	float fEyePos[3], fEyeAng[3];

	GetClientEyePosition(client, fEyePos);
	GetClientEyeAngles(client, fEyeAng);

	TR_TraceRayFilter(fEyePos, fEyeAng, MASK_PLAYERSOLID, RayType_Infinite, TraceFilter2, client);

	if(TR_DidHit())
	{
		switch(TR_GetEntityIndex())
		{
			case -1: return false; // no collision
			case 0: return false; // hit world/wall etc.
			default:  return true; // hit entity
		}	
	}

	return false;
}

stock bool TraceFilter2(int entity, int contentsMask, int client) // ignore if client is not a zombie
{
	if(entity != client && entity > 0 && entity <= MaxClients && GetClientTeam(entity) == CS_TEAM_T)
		return true;

	return false;
}