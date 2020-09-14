#include <sourcemod>
#include <emitsoundany>
#include <sdktools>
#include <sdkhooks>
#include <menu-stocks>
#include <clientprefs>
#include <basecomm>


#pragma semicolon 1;
#pragma newdecls required;

// ************************** Author & Description *************************** 

public Plugin myinfo = 
{
	name = "Sanky Sounds",
	author = "xSLOW",
	description = "Play chat sounds",
	version = "1.2",
	url = "https://steamcommunity.com/profiles/76561193897443537"
};

// ************************** Variables *************************** 

ConVar  g_CvAntiSpam_Time,
        g_CvAntiSpam_SoundsPerTime,
        g_CvSankSounds_AccessFlag,
        g_CvSankSounds_FlagToAvoidAntiSpam,
        g_CvSankSounds_PlayedSound;

char    g_sSoundName[1024][256],
        g_sSoundPath[1024][256];

int g_iSoundsCounter,
    g_iSoundsPlayed[MAXPLAYERS + 1] = 0;

Handle  g_hSankSounds_Cookie = INVALID_HANDLE,
        g_hAntiSpamTimer[MAXPLAYERS + 1] = null;

bool    g_bHasSoundsOn[MAXPLAYERS + 1] = false,
        g_bAlreadyPlayed = false;

// ************************** OnPluginStart *************************** 

public void OnPluginStart()
{
    RegConsoleCmd("say", OnSay);
    RegConsoleCmd("say_team", OnSay);

    RegConsoleCmd("sm_sanky", Command_Sanky);
    RegConsoleCmd("sm_sounds", Command_Sanky);
    RegConsoleCmd("sm_sunete", Command_Sanky);
    RegConsoleCmd("sm_sank", Command_Sanky);
    RegConsoleCmd("sm_sanksounds", Command_Sanky);

    RegAdminCmd("sm_sanksounds_reloadcfg", Command_ReloadCfg, ADMFLAG_ROOT);

    g_hSankSounds_Cookie = RegClientCookie("SankSounds", "Turn it ON/OFF", CookieAccess_Private);

    g_CvAntiSpam_Time = CreateConVar("sm_sanksounds_antispam_time", "90.0", "How often I should reset the anti spam timer?");
    g_CvAntiSpam_SoundsPerTime = CreateConVar("sm_sanksounds_antispam_soundspertime", "1", "How many sounds can I play in << sm_sanksounds_antispam_time >> time?");
    g_CvSankSounds_AccessFlag = CreateConVar("sm_sanksounds_accessflag", "t", "Access to play sank sounds (limited by AntiSpam system)");
    g_CvSankSounds_FlagToAvoidAntiSpam = CreateConVar("sm_sanksounds_flagtoavoidantispam", "z", "Access to play sank sounds (no restriction)");
    g_CvSankSounds_PlayedSound = CreateConVar("sm_sanksounds_playedsound", "20.0", "Time interval to play sounds");

    for(int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if(IsClientValid(iClient))
        {
            g_iSoundsPlayed[iClient] = 0;
            g_hAntiSpamTimer[iClient] = null;
            OnClientCookiesCached(iClient);
        }
    }

    AutoExecConfig(true, "SankSounds");
}

// ************************** OnMapStart *************************** 

public void OnMapStart()
{
    LoadConfig();
    g_bAlreadyPlayed = false;
    for(int iClient = 1; iClient <= MaxClients; iClient++)
    {
        g_iSoundsPlayed[iClient] = 0;
        g_hAntiSpamTimer[iClient] = null;
    }
}

// ************************** OnClientsCookiesCached *************************** 

public void OnClientCookiesCached(int client)
{
    if(!client) return;

    g_bHasSoundsOn[client] = false;
    char cBuffer[8];
    GetClientCookie(client, g_hSankSounds_Cookie, cBuffer, sizeof(cBuffer));

    if(StrEqual(cBuffer, "1", false))
    {
        g_bHasSoundsOn[client] = true;
    }
}

// ************************** OnClientPostAdminCheck *************************** 

public void OnClientPostAdminCheck(int client)
{
    if(IsClientValid(client))
    {
        g_iSoundsPlayed[client] = 0;
        g_hAntiSpamTimer[client] = null;
        //OnClientCookiesCached(client);
        CreateTimer(30.0, Timer_OpenMenuFirstTime, GetClientUserId(client));
    }
}

// ************************** Timer_OpenmenuFirstTime *************************** 

public Action Timer_OpenMenuFirstTime(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);

    if(IsClientValid(client))
    {
        char cBuffer[8];
        GetClientCookie(client, g_hSankSounds_Cookie, cBuffer, sizeof(cBuffer));
        if(!StrEqual(cBuffer, "0") && !StrEqual(cBuffer, "1"))
        {
            ShowEnDisMenu(client);
        }
    }
}

// ************************** Command_ReloadCfg *************************** 

public Action Command_ReloadCfg(int client, int args) 
{
    LoadConfig();
}

// ************************** LoadConfig *************************** 

public void LoadConfig()
{
    PrintToServer("Loading SANK sounds CFG");
    if(FileExists("addons/sourcemod/configs/SankSounds.cfg"))
    {
        KeyValues kv = new KeyValues("SankSounds");
        kv.ImportFromFile("addons/sourcemod/configs/SankSounds.cfg");    

        if (!kv.GotoFirstSubKey())
        {
            delete kv;
        }

        char SoundPath[256], SoundName[256];
        g_iSoundsCounter = 0;

        do
	    {
            KvGetString(kv, "File", SoundPath, 255);
            kv.GetSectionName(SoundName, sizeof(SoundName));
            if(StrContains(SoundName, "|", false))
            {
                char ExplodedString[128][64];
                int ExplodeCounter = ExplodeString(SoundName, "|", ExplodedString, sizeof(ExplodedString), sizeof(ExplodedString[]));

                for(int i = 0; i < ExplodeCounter; i++)
                {
                    strcopy(g_sSoundName[g_iSoundsCounter], sizeof(g_sSoundName[]), ExplodedString[i]);
                    strcopy(g_sSoundPath[g_iSoundsCounter], sizeof(g_sSoundPath), SoundPath);
                    g_iSoundsCounter++;
                }
            }
            else
            {
                strcopy(g_sSoundName[g_iSoundsCounter], sizeof(g_sSoundName[]), SoundName);
                strcopy(g_sSoundPath[g_iSoundsCounter], sizeof(g_sSoundPath[]), SoundPath);
                g_iSoundsCounter++;
            }
	    } while (kv.GotoNextKey());
        delete kv;

        Sounds_Cache();

    }
    else SetFailState("Config files not found. Check if config files are missing.");
}

// ************************** Sounds_Cache *************************** 

public void Sounds_Cache()
{
    for(int i = 0; i < g_iSoundsCounter; i++)
    {
        char FilePathToCheck[256];
        Format(FilePathToCheck, sizeof(FilePathToCheck), "sound/%s", g_sSoundPath[i]);
        if(FileExists(FilePathToCheck))
        {
            char filepath[1024];
            Format(filepath, sizeof(filepath), "sound/%s", g_sSoundPath[i]);
            AddFileToDownloadsTable(filepath);

            char soundpath[1024];
            Format(soundpath, sizeof(soundpath), "*/%s", g_sSoundPath[i]);
            FakePrecacheSound(soundpath);
        } else LogError("Missing sound file: %s", FilePathToCheck);
    }
}

// ************************** OnSay *************************** 

public Action OnSay(int client, int args)
{
    if(IsClientValid(client))
    {
        char ArgText[256];
        GetCmdArgString(ArgText, sizeof(ArgText));
        StripQuotes(ArgText);

        if(strlen(ArgText) > 0)
        {
            if(HasFlagToPlay(client) && !HasFlagToAvoid(client) && g_bHasSoundsOn[client])
            {
                if(!BaseComm_IsClientGagged(client))
                {
                    for(int i = 0; i < g_iSoundsCounter; i++)
                    {
                        if(StrEqual(ArgText, g_sSoundName[i], false))
                        {
                            if(g_iSoundsPlayed[client] < g_CvAntiSpam_SoundsPerTime.IntValue)
                            {
                                if(!g_bAlreadyPlayed)
                                {
                                    char Sound[128];
                                    Format(Sound, sizeof(Sound), "*/%s", g_sSoundPath[i]);

                                    for(int iClient = 1; iClient <= MaxClients; iClient++)
                                    {
                                        if(IsClientValid(iClient) && g_bHasSoundsOn[iClient])
                                        {
                                            EmitSoundToClient(iClient, Sound, SOUND_FROM_PLAYER, SNDCHAN_STATIC, SNDLEVEL_NONE, _, 1.0);
                                        }
                                    }

                                    g_iSoundsPlayed[client]++;
                                    g_bAlreadyPlayed = true;

                                    if(g_hAntiSpamTimer[client] != null)
                                        delete g_hAntiSpamTimer[client];

                                    g_hAntiSpamTimer[client] = CreateTimer(g_CvAntiSpam_Time.FloatValue, Timer_ResetAntiSpam, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
                                    CreateTimer(g_CvSankSounds_PlayedSound.FloatValue, Timer_AlreadyPlayed);
                                } 
                                else PrintToChat(client, "* A \x10sound \x07was already\x01 played a while \x04ago.");
                            }
                            else PrintToChat(client, "* You \x02already \x01played a sound \x04a while ago. \x01Please wait \x03%d\x01 seconds before playing another sound.", RoundFloat(g_CvAntiSpam_Time.FloatValue));
                            break;
                        }
                    }                   
                }
            }
            else if(HasFlagToAvoid(client) && g_bHasSoundsOn[client])
            {
                for(int i = 0; i < g_iSoundsCounter; i++)
                {
                    if(StrEqual(ArgText, g_sSoundName[i], false))
                    {
                        if(!BaseComm_IsClientGagged(client))
                        {
                            char Sound[128];
                            Format(Sound, sizeof(Sound), "*/%s", g_sSoundPath[i]);
                            for(int iClient = 1; iClient <= MaxClients; iClient++)
                            {
                                if(IsClientValid(iClient) && g_bHasSoundsOn[iClient])
                                {
                                    EmitSoundToClient(iClient, Sound, SOUND_FROM_PLAYER, SNDCHAN_STATIC, SNDLEVEL_NONE, _, 1.0);
                                }
                            }
                            break; 
                        }
                    }
                }
            }
        }
    }
    return Plugin_Continue;
}



// ************************** Main Menu *************************** 

public Action Command_Sanky(int client, int args) 
{
    if(IsClientValid(client))
    {
        Menu MainMenu = new Menu(ShowMainMenuHandler, MENU_ACTIONS_DEFAULT);
        MainMenu.SetTitle("[Sanky Sounds] \nMain menu");
        MainMenu.AddItem("endis", "Enable/Disable sounds");
        MainMenu.AddItem("soundlist", "Sound list");

        MainMenu.ExitButton = true;
        MainMenu.Display(client, 15);
    }
    return Plugin_Handled;
}

public int ShowMainMenuHandler(Menu MainMenu, MenuAction action, int param1, int param2)
{
    int client = param1;

    switch(action)
    {
        case MenuAction_Select:
        {
            char info[128];
            MainMenu.GetItem(param2, info, sizeof(info));
            if(StrEqual(info, "endis"))
            {
                ShowEnDisMenu(client);
            }
            else if(StrEqual(info, "soundlist"))
            {
                ShowSoundsList(client);
            }
        }
        case MenuAction_End:
        {
            delete MainMenu;
        }
    }
}

// ************************** Enable/Disable menu ***************************

public void ShowEnDisMenu(int client)
{
    if(IsClientValid(client))
    {
        Menu EnDisMenu = new Menu(EnDisHandler, MENU_ACTIONS_DEFAULT);

        char MenuTitle[128];
        Format(MenuTitle, sizeof(MenuTitle), "[Sanky Sounds] \nDo you want to enable Chat Sounds?");
        EnDisMenu.SetTitle(MenuTitle);

        EnDisMenu.AddItem("Yes", "Yes");
        EnDisMenu.AddItem("No", "No");

        EnDisMenu.ExitButton = false;
        EnDisMenu.Display(client, 15);
    }
}

public int EnDisHandler(Menu EnDisMenu, MenuAction action, int param1, int param2)
{
    int client = param1;

    switch(action)
    {
        case MenuAction_Select:
        {
            char info[128];
            EnDisMenu.GetItem(param2, info, sizeof(info));
            if(StrEqual(info, "Yes"))
            {
                PrintToChat(client, "* You \x04ENABLED \x01chat sounds");
                g_bHasSoundsOn[client] = true;
                SetClientCookie(client, g_hSankSounds_Cookie, "1");
            }
            else if(StrEqual(info, "No"))
            {
                PrintToChat(client, "* You \x02DISABLED \x01chat sounds");
                g_bHasSoundsOn[client] = false;
                SetClientCookie(client, g_hSankSounds_Cookie, "0");
            }
        }
        case MenuAction_End:
        {
            delete EnDisMenu;
        }
    }
}

// ************************** Sound List menu ***************************

public void ShowSoundsList(int client)
{
    if(IsClientValid(client))
    {
        Menu SoundsList = new Menu(ShowSoundsListHandler, MENU_ACTIONS_DEFAULT);

        char MenuTitle[128];
        Format(MenuTitle, sizeof(MenuTitle), "[Sanky Sounds] \nSounds List\nSounds count: %d", g_iSoundsCounter);
        SoundsList.SetTitle(MenuTitle);
        for(int i = 0; i < g_iSoundsCounter; i++)
        {
            SoundsList.AddItem("GoBack", g_sSoundName[i]);
        }

        SoundsList.ExitButton = true;
        SoundsList.Display(client, 15);
    }
}

public int ShowSoundsListHandler(Menu SoundsList, MenuAction action, int param1, int param2)
{
    int client = param1;

    switch(action)
    {
        case MenuAction_Select:
        {
            char info[128];
            SoundsList.GetItem(param2, info, sizeof(info));
            if(StrEqual(info, "GoBack"))
            {
                ShowSoundsList(client);
            }
        }
        case MenuAction_End:
        {
            delete SoundsList;
        }
    }
}

// ************************** Timer_AlreadyPlayed ***************************

public Action Timer_AlreadyPlayed(Handle timer)
{
    g_bAlreadyPlayed = false;
}


// ************************** Timer_ResetAntiSpam ***************************

public Action Timer_ResetAntiSpam(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    g_iSoundsPlayed[client] = 0;
    g_hAntiSpamTimer[client] = null;
}

// ************************** Small functions & stuff ***************************

stock bool IsClientValid(int client)
{
    return (0 < client <= MaxClients) && IsClientInGame(client) && !IsFakeClient(client);
}

stock void FakePrecacheSound(const char[] szPath)
{
	AddToStringTable(FindStringTable("soundprecache"), szPath);
}

stock bool HasFlagToAvoid(int client) 
{ 
    char ConVarString[32];
    GetConVarString(g_CvSankSounds_FlagToAvoidAntiSpam, ConVarString, sizeof(ConVarString));
    int FLAG = ReadFlagString(ConVarString);
    return (CheckCommandAccess(client, "", FLAG, true));
}  

stock bool HasFlagToPlay(int client) 
{ 
    char ConVarString[32];
    GetConVarString(g_CvSankSounds_AccessFlag, ConVarString, sizeof(ConVarString));
    int FLAG = ReadFlagString(ConVarString);
    return (CheckCommandAccess(client, "", FLAG, true));
}  
