#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <multicolors>
#include <zr_lasermines>

#pragma tabsize 0

ConVar g_cvMaxPropDamage;
ConVar g_cvBlockNades;
ConVar g_cvMaxNadeDamage;
ConVar g_cvKick;
ConVar g_cvKickLimit;
ConVar g_cvAdminOnline;
ConVar g_cvMaxPropDistance;
ConVar g_cvMinPropDistance;
ConVar g_cvResetPropDamage;
ConVar g_cvResetPropDamageTime;
ConVar g_cvHudLocation;
ConVar g_cvHudColors;

Handle g_hHudMsg;

int g_iPropDamage[MAXPLAYERS +1];
int g_iTimesSlayed[MAXPLAYERS +1];
int g_iLastPropShotTime[MAXPLAYERS +1];
int g_iPropGrenadeDamage;
int g_iHudColor[4];

float fHudLocation[2];

bool g_bRoundEnd = false;
bool g_bNadeMsg = false;
bool g_bNadesBlocked = false;
bool g_bAdminOnline = false;
bool g_bLastChance[MAXPLAYERS +1];
bool g_bBlockDamage[MAXPLAYERS +1];

char LogFile[128];
char MapName[128];

public Plugin myinfo =
{
	name = "[ZR] PropWatch",
	author = "ire.",
	description = "Automatically slay/kick players who shoot props of their teammates",
	version = "1.6"
};

public void OnPluginStart()
{
	RegAdminCmd("sm_propdist", CmdPropDistance, ADMFLAG_BAN, "Calculate the distance between you and a prop");
	RegAdminCmd("sm_clientdist", CmdClientDistance, ADMFLAG_BAN, "Calculate the distance between you and a client");
	RegAdminCmd("sm_unblocknades", CmdUnblockNades, ADMFLAG_BAN, "Unblock grenade blast damage after being blocked");
	
	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("player_death", Event_PlayerDeath);
	
	g_cvMaxPropDamage = CreateConVar("sm_propwatch_maxdmg", "2500", "Amount of damage a player can do to friendly props before slay");
	g_cvBlockNades = CreateConVar("sm_propwatch_blocknades", "1", "Block grenade blast damage on friendly props? [1 = yes 0 = no]");
	g_cvMaxNadeDamage = CreateConVar("sm_propwatch_maxnadedmg", "1000", "Amount of damage from grenades before blocking");
	g_cvKick = CreateConVar("sm_propwatch_kick", "1", "Kick players who have been slayed for shooting props enough many times [1 = yes 0 = no]");
	g_cvKickLimit = CreateConVar("sm_propwatch_kicklimit", "2", "Amount of slays before kicking the player");
	g_cvAdminOnline = CreateConVar("sm_propwatch_admin", "1", "Enable or disable plugin while there are admins online [1 = enable 0 = disable]");
	g_cvMaxPropDistance = CreateConVar("sm_propwatch_maxdist", "200", "Exclude props that are farther than this from the owner");
	g_cvMinPropDistance = CreateConVar("sm_propwatch_mindist_scale", "0.65", "Multiplier to scale the player model to check if a player is stuck in a prop [1 = fully stuck 0.5 = half stuck]");
	g_cvResetPropDamage = CreateConVar("sm_propwatch_resetdmg", "1", "Reset dealt prop damage after a certain period of time if a player has not shot friendly props [1 = yes 0 = no]");
	g_cvResetPropDamageTime = CreateConVar("sm_propwatch_resetdmg_time", "60", "Amount of seconds before resetting dealt prop damage");
	g_cvHudLocation = CreateConVar("sm_propwatch_hudlocation", "0.8 0.5", "X and Y coordinates of the HUD text");
	g_cvHudColors = CreateConVar("sm_propwatch_hudcolors", "0 155 0 255", "RGBA color values of the HUD text");
	HookConVarChange(g_cvHudLocation, OnConVarChanged);
	HookConVarChange(g_cvHudColors, OnConVarChanged);
	AutoExecConfig();
	
	BuildPath(Path_SM, LogFile, sizeof(LogFile), "logs/propwatch.cfg");
	
	g_hHudMsg = CreateHudSynchronizer();
	
	LoadTranslations("propwatch.phrases");
}

public void OnMapStart()
{
	GetCurrentMap(MapName, sizeof(MapName));
}

public void OnConfigsExecuted()
{
	SetHudColors();
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	OnConfigsExecuted();
}

public void OnClientPostAdminCheck(int client)
{
	ResetClientVariables(client);
	CheckOnlineAdmins();
}

public void OnClientDisconnect(int client)
{
	ResetClientVariables(client);
	CheckOnlineAdmins();
}

public Action CmdPropDistance(int client, int args)
{
	int g_iTarget = GetClientAimTarget(client, false);
	
	if(IsValidEntity(g_iTarget))
	{
		CPrintToChat(client, "%t", "PropDistance", CalculateDistance(client, g_iTarget));
	}
	
	return Plugin_Handled;
}

public Action CmdClientDistance(int client, int args)
{
	int g_iTarget = GetClientAimTarget(client, true);
	
	if(IsValidEntity(g_iTarget))
	{
		CPrintToChat(client, "%t", "ClientDistance", CalculateDistance(client, g_iTarget));
	}
	
	return Plugin_Handled;
}

float CalculateDistance(int origin, int target)
{
	float fOrigin[3], fTarget[3];
	
	GetEntPropVector(origin, Prop_Data, "m_vecOrigin", fOrigin);
	GetEntPropVector(target, Prop_Data, "m_vecOrigin", fTarget);
	
	return GetVectorDistance(fOrigin, fTarget);
}

public Action CmdUnblockNades(int client, int args)
{
	if(g_bNadesBlocked)
	{
		g_bNadesBlocked = false;
		g_bNadeMsg = false;
		g_iPropGrenadeDamage = 0;
		CPrintToChat(client, "%t", "UnblockedNades");
	}
	
	return Plugin_Handled;
}

public void OnEntityCreated(int entity, const char[] classname)
{
    SDKHook(entity, SDKHook_SpawnPost, OnSpawnPost);
}

public void OnSpawnPost(int entity)
{
    char ClassName[64];
	GetEntityClassname(entity, ClassName, sizeof(ClassName));
	
    if(StrEqual(ClassName, "prop_physics", false) || StrEqual(ClassName, "prop_physics_multiplayer", false) || StrEqual(ClassName, "prop_physics_override", false))
	{
		SDKHook(entity, SDKHook_OnTakeDamage, OnTakeDamage);
	}
}

public Action OnTakeDamage(int entity, int& attacker, int& inflictor, float& damage, int& damagetype)
{	
	if(!IsValidAttacker(attacker))
	{
	    return Plugin_Continue;
	}
	
	if(g_bBlockDamage[attacker])
	{
		return Plugin_Handled;
	}
	
	if(!g_cvAdminOnline.BoolValue && g_bAdminOnline)
	{
		return Plugin_Continue;
	}
	
	if(g_bRoundEnd)
	{
		return Plugin_Continue;
	}
	
	if(ZR_IsEntityLasermine(entity))
	{
		return Plugin_Continue;
	}
	
	int g_iOwner = GetEntPropEnt(entity, Prop_Send, "m_PredictableID");
	
	if(attacker != g_iOwner && g_iOwner > 0)
	{
		if(GetClientTeam(attacker) == 3 && GetClientTeam(g_iOwner) == 3)
		{
			float fOwnerOrigin[3], fVictimOrigin[3];
			
			GetEntPropVector(g_iOwner, Prop_Data, "m_vecOrigin", fOwnerOrigin);
			GetEntPropVector(entity, Prop_Data, "m_vecOrigin", fVictimOrigin);
			
			if(GetVectorDistance(fOwnerOrigin, fVictimOrigin) <= g_cvMaxPropDistance.IntValue && !IsAttackerStuckInProp(attacker) && !IsZombieInAttackersAim(attacker))
			{	
				g_iPropDamage[attacker] += RoundToZero(damage);
				
				if(g_cvResetPropDamage.BoolValue)
				{
					if(GetTime() > g_iLastPropShotTime[attacker] + g_cvResetPropDamageTime.IntValue)
					{
						g_iPropDamage[attacker] = 0;
					}
					
					g_iLastPropShotTime[attacker] = GetTime();
				}
				
				SetHudTextParams(fHudLocation[0], fHudLocation[1], 1.0, g_iHudColor[0], g_iHudColor[1], g_iHudColor[2], g_iHudColor[3]);
				
				if(g_iPropDamage[attacker] <= g_cvMaxPropDamage.IntValue)
				{
					if(g_cvKick.BoolValue)
					{
						ShowSyncHudText(attacker, g_hHudMsg, "%t", "HudTextKick", g_iPropDamage[attacker], g_cvMaxPropDamage.IntValue, g_iTimesSlayed[attacker], g_cvKickLimit.IntValue);
					}
					
					else
					{
						ShowSyncHudText(attacker, g_hHudMsg, "%t", "HudText", g_iPropDamage[attacker], g_cvMaxPropDamage.IntValue);
					}
				}
			}
		}
		
		if(g_cvBlockNades.BoolValue && damagetype == DMG_BLAST)
		{
			if(GetClientTeam(g_iOwner) == 3)
			{
				if(g_iPropGrenadeDamage >= g_cvMaxNadeDamage.IntValue)
				{
					if(!g_bNadeMsg)
					{
						CPrintToChatAll("%t", "GrenadeBlastDisabledAll");
						g_bNadeMsg = true;
						g_bNadesBlocked = true;
					}
				
					if(g_bNadesBlocked)
					{
						return Plugin_Handled;
					}
				}
				
				else
				{
					g_iPropGrenadeDamage += RoundToZero(damage);
				}
			}
		}
	}
	
	if(g_iPropDamage[attacker] >= g_cvMaxPropDamage.IntValue)
	{
		g_iTimesSlayed[attacker]++;
		
		if(g_cvKick.BoolValue)
		{
			if(!g_bLastChance[attacker])
			{
				g_bBlockDamage[attacker] = true;
				SlayPlayer(attacker);
			}
		}
		
		else
		{
			g_bBlockDamage[attacker] = true;
			SlayPlayer(attacker);
		}
	}
	
	if(g_cvKick.BoolValue && g_iTimesSlayed[attacker] == g_cvKickLimit.IntValue)
	{
		g_bLastChance[attacker] = true;
	}
	
	if(g_cvKick.BoolValue && g_iTimesSlayed[attacker] > g_cvKickLimit.IntValue)
	{
		g_bBlockDamage[attacker] = true;
		KickPlayer(attacker);
	}
	
	return Plugin_Continue;
}

void SlayPlayer(int attacker)
{
	char SteamID[32];
	GetClientAuthId(attacker, AuthId_Steam2, SteamID, sizeof(SteamID));
	
	CPrintToChat(attacker, "%t", "SlayTextClient");
	CPrintToChatAll("%t", "SlayTextAll", attacker, SteamID);
	LogToFile(LogFile, "%t", "LogSlay", attacker, SteamID, MapName);
	
	ForcePlayerSuicide(attacker);
}

void KickPlayer(int attacker)
{
	char SteamID[32];
	GetClientAuthId(attacker, AuthId_Steam2, SteamID, sizeof(SteamID));
	
	CPrintToChatAll("%t", "KickTextAll", attacker, SteamID);
	LogToFile(LogFile, "%t", "LogKick", attacker, SteamID, MapName);
	
	KickClient(attacker, "%t", "KickTextClient");
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i))
		{
			ResetClientVariables(i);
		}
	}
	
	g_iPropGrenadeDamage = 0;
	g_bRoundEnd = false;
	g_bNadeMsg = false;
	g_bNadesBlocked = false;
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	g_bRoundEnd = true;
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int g_iVictim = GetClientOfUserId(event.GetInt("userid"));
	
	if(IsValidClient(g_iVictim))
	{
		if(g_cvKick.BoolValue)
		{
			g_iPropDamage[g_iVictim] = 0;
			g_bBlockDamage[g_iVictim] = false;
		}
		
		else
		{
			g_iPropDamage[g_iVictim] = 0;
			g_iTimesSlayed[g_iVictim] = 0;
			g_bBlockDamage[g_iVictim] = false;
		}
	}
}

void SetHudColors()
{
	char Location[16], Colors[16], LocationBuffer[2][8], ColorBuffer[4][4];
	g_cvHudLocation.GetString(Location, sizeof(Location));
	g_cvHudColors.GetString(Colors, sizeof(Colors));
	
	ExplodeString(Location, " ", LocationBuffer, sizeof(LocationBuffer), sizeof(LocationBuffer[]));
	ExplodeString(Colors, " ", ColorBuffer, sizeof(ColorBuffer), sizeof(ColorBuffer[]));
	
	fHudLocation[0] = StringToFloat(LocationBuffer[0]);
	fHudLocation[1] = StringToFloat(LocationBuffer[1]);
	
	g_iHudColor[0] = StringToInt(ColorBuffer[0]);
	g_iHudColor[1] = StringToInt(ColorBuffer[1]);
	g_iHudColor[2] = StringToInt(ColorBuffer[2]);
	g_iHudColor[3] = StringToInt(ColorBuffer[3]);
}

void ResetClientVariables(int client)
{
	g_iPropDamage[client] = 0;
	g_iTimesSlayed[client] = 0;
	g_bLastChance[client] = false;
	g_bBlockDamage[client] = false;
}

void CheckOnlineAdmins()
{
	g_bAdminOnline = false;
	
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i) && CheckCommandAccess(i, "", ADMFLAG_GENERIC, true))
		{
			g_bAdminOnline = true;
			break;
		}
	}
}

bool IsValidClient(int client)
{
    return(IsClientInGame(client) && !IsFakeClient(client));
}

bool IsValidAttacker(int client)
{
	return(0 < client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client) && IsPlayerAlive(client));
}

bool IsAttackerStuckInProp(int client)
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

bool TraceFilter(int entity, int contentsMask) // ignore clients and lasermines
{
	if(entity > MaxClients)
	{
		if(!ZR_IsEntityLasermine(entity))
		{
			return true;
		}
	}
	
	return false;
}

bool IsZombieInAttackersAim(int client)
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

bool TraceFilter2(int entity, int contentsMask, int client) // ignore if client is not a zombie
{
	if(entity != client && entity > 0 && entity <= MaxClients)
	{
		if(GetClientTeam(entity) == 2)
		{
			return true;
		}
	}
	
	return false;
}