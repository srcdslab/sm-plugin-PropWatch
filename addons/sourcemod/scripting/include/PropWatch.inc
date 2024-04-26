#if defined _PropWatch_Included
	#endinput
#endif
#define _PropWatch_Included

/**
 * Called after a player get punished
 * 
 * @param client    	Punished client UserId
 * @param steamid    	Punished client SteamId
 * @param mapname      	Map name where the punishment happened
 * @noreturn
 */
forward void PropWatch_OnClientPunished(int client, char[] steamid, char[] mapname);

public SharedPlugin __pl_PropWatch =
{
	name = "PropWatch",
	file = "PropWatch.smx",
	#if defined REQUIRE_PLUGIN
	required = 1
	#else
	required = 0
	#endif
};