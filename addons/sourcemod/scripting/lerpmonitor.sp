#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <colors>


public Plugin myinfo = {
    name        = "LerpMonitor",
    author      = "ProdigySim, TouchMe",
    description = "Monitors And Tracks Every Player's Lerp",
    version     = "build_0000",
    url         = "https://github.com/TouchMe-Inc/l4d2_lerpmonitorr"
};


#define TRANSLATIONS            "lerpmonitor.phrases"

#define TEAM_SPECTATORS 1


enum struct LerpInfo
{
    float Value;
    int Changes;
}

StringMap g_smLerpsValue = null;

ConVar
    g_cvAllowedLerpChanges = null,
    g_cvMinLerp = null,
    g_cvMaxLerp = null
;

int    g_iAllowedLerpChanges = 0;
float  g_fMinLerp = 0.0;
float  g_fMaxLerp = 0.0;

bool g_bLateLoad = false;


public APLRes AskPluginLoad2(Handle hSelf, bool bLate, char[] error, int err_max)
{
    g_bLateLoad = bLate;

    return APLRes_Success;
}

public void OnPluginStart()
{
    LoadTranslations(TRANSLATIONS);

    g_cvAllowedLerpChanges = CreateConVar(
        "sm_allowed_lerp_changes", "5",
        "Allowed number of lerp changes for a half",
        FCVAR_NONE, true, 0.0, false, 0.0
    );
    g_iAllowedLerpChanges = g_cvAllowedLerpChanges.IntValue;
    g_cvAllowedLerpChanges.AddChangeHook(ChangeHook_AllowedLerpChanges);

    g_cvMinLerp = CreateConVar(
        "sm_min_lerp", "0",
        "Minimum Value Of Lerp",
        FCVAR_NONE, true, 0.0, true, 500.0
    );
    g_fMinLerp = g_cvMinLerp.FloatValue;
    g_cvMinLerp.AddChangeHook(ChangeHook_MinLerp);

    g_cvMaxLerp = CreateConVar(
        "sm_max_lerp", "100",
        "Maximum Value Of Lerp",
        FCVAR_NONE, true, 0.0, true, 500.0
    );
    g_fMaxLerp = g_cvMaxLerp.FloatValue;
    g_cvMaxLerp.AddChangeHook(ChangeHook_MaxLerp);

    HookEvent("player_team", Event_PlayerTeam);
    AddCommandListener(Listener_OnPlayerJoinTeam, "jointeam");

    g_smLerpsValue = new StringMap();

    if (g_bLateLoad)
    {
        for (int iClient = 1; iClient <= MaxClients; iClient ++)
        {
            if (!IsClientInGame(iClient) || IsFakeClient(iClient))
                continue;

            ProcessClientLerp(iClient);
        }
    }
}

void ChangeHook_AllowedLerpChanges(ConVar cv, const char[] szOldVal, const char[] szNewVal) {
    g_iAllowedLerpChanges = g_cvAllowedLerpChanges.IntValue;
}

void ChangeHook_MinLerp(ConVar cv, const char[] szOldVal, const char[] szNewVal) {
    g_fMinLerp = g_cvMinLerp.FloatValue;
}

void ChangeHook_MaxLerp(ConVar cv, const char[] szOldVal, const char[] szNewVal) {
    g_fMaxLerp = g_cvMaxLerp.FloatValue;
}

public void OnMapEnd() {
    g_smLerpsValue.Clear();
}

public void OnClientSettingsChanged(int iClient)
{
    if (!IsClientInGame(iClient) || IsFakeClient(iClient))
        return;

    ProcessClientLerp(iClient);
}

void Event_PlayerTeam(Event event, char[] szEventName, bool bDontBroadcast)
{
    if (event.GetInt("team") == TEAM_SPECTATORS) {
        return;
    }

    int iUserId = event.GetInt("userid");
    if (GetClientOfUserId(iUserId) <= 0) {
        return;
    }

    CreateTimer(0.1, Timer_PlayerTeam, iUserId, TIMER_FLAG_NO_MAPCHANGE);
}

Action Timer_PlayerTeam(Handle hTimer, int iUserId)
{
    int iClient = GetClientOfUserId(iUserId);

    if (iClient <= 0 || !IsClientInGame(iClient) || IsFakeClient(iClient)) {
        return Plugin_Stop;
    }

    ProcessClientLerp(iClient);
    return Plugin_Stop;
}

Action Listener_OnPlayerJoinTeam(int iClient, const char[] sCmd, int iArgs)
{
    float fClientLerp = GetClientLerp(iClient);

    if (IsInvalidLerp(fClientLerp))
    {
        CPrintToChat(iClient, "%T%T", "TAG", iClient, "INVALID_LERP", iClient, fClientLerp, g_fMinLerp, g_fMaxLerp);
        return Plugin_Handled;
    }

    if (g_iAllowedLerpChanges == 0) {
        return Plugin_Continue;
    }

    char szClientSteamId[32];
    GetClientAuthId(iClient, AuthId_Steam2, szClientSteamId, sizeof(szClientSteamId), true);

    LerpInfo lerp;
    if (!g_smLerpsValue.GetArray(szClientSteamId, lerp, sizeof(LerpInfo))) {
        return Plugin_Continue;
    }

    if (lerp.Changes > g_iAllowedLerpChanges && lerp.Value != fClientLerp)
    {
        CPrintToChat(iClient, "%T%T", "TAG", iClient, "BACK_TO_LAST_LERP", iClient, fClientLerp, lerp.Value);
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

void ProcessClientLerp(int iClient)
{
    if (GetClientTeam(iClient) <= TEAM_SPECTATORS) {
        return;
    }

    float fClientLerp = GetClientLerp(iClient);

    if (IsInvalidLerp(fClientLerp))
    {
        ChangeClientTeam(iClient, TEAM_SPECTATORS);
        CPrintToChatAllEx(iClient, "%t%t", "TAG", "MOVE_TO_SPEC", iClient, fClientLerp);
        CPrintToChat(iClient, "%T%T", "TAG", iClient, "INVALID_LERP", iClient, fClientLerp, g_fMinLerp, g_fMaxLerp);
        return;
    }

    char szClientSteamId[32];
    GetClientAuthId(iClient, AuthId_Steam2, szClientSteamId, sizeof(szClientSteamId), true);

    LerpInfo lerp;
    if (!g_smLerpsValue.GetArray(szClientSteamId, lerp, sizeof(LerpInfo)))
    {
        lerp.Value = fClientLerp;
        lerp.Changes = 0;
        g_smLerpsValue.SetArray(szClientSteamId, lerp, sizeof(LerpInfo));
        return;
    }

    if (lerp.Value == fClientLerp) {
        return;
    }

    if (g_iAllowedLerpChanges == 0)
    {
        CPrintToChatAllEx(iClient, "%t%t", "TAG", "LERP_CHANGED", iClient, lerp.Value, fClientLerp);
        lerp.Value = fClientLerp;
        g_smLerpsValue.SetArray(szClientSteamId, lerp, sizeof(LerpInfo));
        return;
    }

    int iNewChanges = lerp.Changes + 1;
    CPrintToChatAllEx(iClient, "%t%t", "TAG", "LERP_CHANGED_WITH_LIMIT", iClient, lerp.Value, fClientLerp, iNewChanges, g_iAllowedLerpChanges);

    if (iNewChanges > g_iAllowedLerpChanges && lerp.Value != fClientLerp)
    {
        ChangeClientTeam(iClient, TEAM_SPECTATORS);
        CPrintToChat(iClient, "%T%T", "TAG", iClient, "BACK_TO_LAST_LERP", iClient, fClientLerp, lerp.Value);
        return;
    }

    lerp.Value = fClientLerp;
    lerp.Changes = iNewChanges;
    g_smLerpsValue.SetArray(szClientSteamId, lerp, sizeof(LerpInfo));
}

bool IsInvalidLerp(float fLerp) {
    return (FloatCompare(fLerp, g_fMinLerp) == -1) || (FloatCompare(fLerp, g_fMaxLerp) == 1);
}

float GetClientLerp(int iClient)
{
    char szLerp[16];
    GetClientInfo(iClient, "cl_interp", szLerp, sizeof(szLerp));
    return StringToFloat(szLerp) * 1000.0;
}
