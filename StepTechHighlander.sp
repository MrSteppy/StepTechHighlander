#include <sourcemod>
#include <timers>
#include <tf2_stocks>
#include <NamePool.sp>
#include <str_util.sp>

#define NAME "StepTechHighlander"
#define VERSION "1.0.0-SNAPSHOT"

#define MAX_MAP_NAME_LENGTH 32
#define MAX_CMD_LENGTH 64
#define MAX_CMD_DESC_LENGTH 255
#define MAX_COMMANDS 16
#define MAX_TEAM_ID_LENGTH 16
#define COMP_SIZE 9
#define MAX_CLASS_ID_LENGTH 16

#define RESTART_TOURNAMENT_CMD "mp_tournament_restart\n"
#define ANY_CLASS_INDEX 9
#define CLASSES_SIZE 9
#define LOBBY_MODE_COUNT_DOWN 10
#define LOBBY_MODE_INFO_INTERVAL 5.0
#define ACK_COUNT_DOWN 5

public Plugin myinfo = {
  name = NAME,
  author = "Steppy",
  description = "Enables highlander mode",
  version = VERSION,
  url = "-"
}

Class classes[CLASSES_SIZE];
ConVar cvarTeamSize = null;
ConVar cvarMpTournament = null;
ConVar cvarMpRestartGame = null;
ConVar cvarTfBotQuota = null;
ConVar cvarTfBotDifficulty = null;
CommandInfo commands[MAX_COMMANDS];
int commandsLen = 0;
ReadyState readyState;
NamePool namePool;

int fullRoundsPlayed = 0;

public void OnPluginStart() {
  LogMessage("Starting %s v%s", NAME, VERSION);

  DefClass(TFClass_Scout, "scout", true);
  DefClass(TFClass_Soldier, "soldier");
  DefClass(TFClass_Pyro, "pyro");
  DefClass(TFClass_DemoMan, "demoman");
  DefClass(TFClass_Heavy, "heavyweapons");
  DefClass(TFClass_Engineer, "engineer");
  DefClass(TFClass_Medic, "medic");
  DefClass(TFClass_Sniper, "sniper");
  DefClass(TFClass_Spy, "spy");

  //con vars
  cvarTeamSize = CreateConVar("st_teamsize", "9", "To how many players each team should have", FCVAR_NOTIFY, true, 0.0);
  AutoExecConfig();

  cvarMpTournament = FindConVar("mp_tournament");
  cvarMpTournament.AddChangeHook(Event_MpTournamentChange);
  cvarMpTournament.IntValue = 1;
  cvarMpRestartGame = FindConVar("mp_restartgame");
  cvarTfBotQuota = FindConVar("tf_bot_quota");
  cvarTfBotDifficulty = FindConVar("tf_bot_difficulty");

  //some con var settings
  FindConVar("tf_bot_keep_class_after_death").IntValue = 1; //make sure bots don't just switch their class, since we manage that
  FindConVar("mp_autoteambalance").IntValue = 0; //make sure bots stay in the team we assign them
  FindConVar("tf_bot_reevaluate_class_in_spawnroom").IntValue = 0; //don't suicide

  //commands
  RegCommand("st_help", Command_Help, "- Displays a command overview");
  RegCommand("st_map", Command_Map, "[mapname]|random - Changes the map");
  RegCommand("st_team_size", Command_TeamSize, "[teamsize] - Set how many players each team should have");
  RegCommand("st_tp_bots", Command_Teleport_Bots, "- Teleports all bots of your team to your location");
  RegCommand("st_lobby", Command_Lobby, "<clean> - Switch to lobby mode. Use clean lobby to kick all bots.");
  RegCommand("eggseck", Command_Eggseck, "start|pause - starts or pauses the match (Bitte hau mich nicht, Nepa, der Command war Craftis Idee ^^')");
  RegCommand("st_update_team_comp", Command_UpdateTeamComp, "- Update the classes of the bots");
  RegCommand("st_difficulty", Command_Difficulty, "[0-3] - Change the bot difficulty");
  RegCommand("st_restart", Command_Restart, "<[inSecs]> - Restarts the server in the specified number of seconds");
  RegCommand("menu", Command_Menu, "- open a quick access menu for some of the commands");

  RegAdminCmd("st_namepool_add", Command_NamePoolAdd, ADMFLAG_GENERIC, "[class name]|[class id]|any [names...] - add names to the namepool");
  RegAdminCmd("st_test", Command_Test, ADMFLAG_GENERIC, "The usual test command");

  //listener
  HookEvent("tournament_stateupdate", Event_ReadyUp);
  HookEvent("player_changeclass", Event_PlayerChangeClass);
  HookEvent("teamplay_round_win", Event_TeamplayRoundWin);
  HookEvent("player_team", Event_PlayerChangeTeam);

  ServerCommand("exec namepool\n"); //reload namepool

  StartLobbyMode(.clean = true);
  int playerCount = GetPlayerCount();
  if (playerCount > 0) {
    //in case we got reloaded
    CreateTimer(0.0, Timer_UpdateTeamComp); //delay, so we don't interfere with clean lobby
  }

  //timers
  CreateTimer(LOBBY_MODE_INFO_INTERVAL, Timer_LobbyModeInfo, _, TIMER_REPEAT);
}

public void OnClientConnected(int client) {
  if (IsBot(client)) return;

  if (GetPlayerCount() == 1) {
    //first player to join -> clean lobby start
    StartLobbyMode(.clean = true);
  }
}

public void OnMapStart() {
  StartLobbyMode(.clean = true);
}

int GetPlayerCount() {
  int count = 0;
  for (int client = 1; client < MaxClients; client++) {
    if (!IsClientConnected(client)) continue;
    if (IsBot(client)) continue;
    count++;
  }
  return count;
}

void DefClass(TFClassType classtype, char[] id, bool clean = false) {
  static int index = 0;
  if (clean) {
    index = 0;
  }
  classes[index].classType = classtype;
  strcopy(classes[index].id, MAX_CLASS_ID_LENGTH, id);
  classes[index].index = index;

  index++;
}

Class Wrap(TFClassType classtype) {
  for (int i = 0; i < sizeof(classes); i++) {
    if (classes[i].classType == classtype) {
      return classes[i];
    }
  }
  ThrowError("Invalid class type");
  //just here to please the compiler
  Class c;
  return c;
}

void RegCommand(const char[] name, ConCmd executor, char[] description, int flags = 0) {
  RegConsoleCmd(name, executor, description, flags);
  CommandInfo info;
  strcopy(info.name, sizeof(info.name), name);
  strcopy(info.description, sizeof(info.description), description);
  commands[commandsLen++] = info;
}

enum struct Class {
  TFClassType classType;
  char id[16];
  int index;
}

enum struct CommandInfo {
  char name[MAX_CMD_LENGTH];
  char description[MAX_CMD_DESC_LENGTH];
}

void Log4All(int client, const char[] msg, any ...) {
  char clientName[MAX_NAME_LENGTH];
  GetClientName(client, clientName, sizeof(clientName));
  
  char prefixFormat[] = "[INFO](%s) ";
  char prefix[MAX_NAME_LENGTH + sizeof(prefixFormat)];
  Format(prefix, sizeof(prefix), prefixFormat, clientName);

  int messageSize = strlen(msg) + 255;
  char[] message = new char[messageSize];
  VFormat(message, messageSize, msg, 3);

  PrintToChatAll("%s%s", prefix, message);
  PrintToServer("%s%s", prefix, message);
}

int GetClientsInTeam(TFTeam team, int[] buf, int bufSize) {
  int teamSize = 0;

  for (int client = 1; client <= MaxClients; client++) {
    if (teamSize >= bufSize) break;

    if (IsClientInGame(client) && TF2_GetClientTeam(client) == team) {
      buf[teamSize++] = client;
    }
  }

  return teamSize;
}

bool isBotOnlyTeam(TFTeam team) {
  int[] teamClients = new int[MaxClients];
  int teamSize = GetClientsInTeam(team, teamClients, MaxClients);
  for (int i = 0; i < teamSize; i++) {
    int client = teamClients[i];
    if (!IsBot(client)) {
      return false;
    }
  }
  return true;
}

/**
 * Checks whether the provided client is a bot
 * 
 * @return true if the client is a bot, false if it is a player, an invalid client or not connected
 */
bool IsBot(int client) {
  return client >= 0 && client <= MaxClients && IsClientConnected(client) && IsFakeClient(client);
}

int GetClientByName(const char[] name) {
  for (int client = 1; client < MaxClients; client++) {
    if (!IsClientConnected(client)) continue;
    char clientName[MAX_NAME_LENGTH];
    GetClientName(client, clientName, sizeof(clientName));
    if (strcmp(clientName, name) == 0) {
      return client;
    }
  }
  return 0;
}

//commands

Action Command_Test(int client, int args) {
  StartLobbyModeTimed();
  return Plugin_Handled;
}

Action Command_Help(int client, int args) {
  ReplyToCommand(client, "%s v%s", NAME, VERSION);
  ReplyToCommand(client, "Values in [] need to be replaced, values in <> are optional. '!' is only required in chat, not in console.")
  for (int i = 0; i < commandsLen; i++) {
    ReplyToCommand(client, "!%s %s", commands[i].name, commands[i].description);
  }
  return Plugin_Handled;
}

Action Command_TeamSize(int client, int args) {
  if (args == 0) {
    ReplyToCommand(client, "Current team size is %d", cvarTeamSize.IntValue);
    return Plugin_Handled;
  }

  int newSize;
  if (GetCmdArgIntEx(1, newSize) && newSize >= 0) {
    int prevSize = cvarTeamSize.IntValue;
    cvarTeamSize.IntValue = newSize;

    Log4All(client, "set team size from %d to %d", prevSize, newSize);

    UpdateTeamComposition(.playersPerTeam = newSize);
  } else {
    ReplyToCommand(client, "team size must be a positive integer");
  }

  return Plugin_Handled;
}

char nextMap[MAX_MAP_NAME_LENGTH];
Handle mapChangeTimer = null;

bool EqualsRandom(const char[] str) {
  return strcmp(str, "random", false) == 0;
}

Action Command_Map(int client, int args) {
  char mapName[MAX_MAP_NAME_LENGTH];
  GetCmdArg(1, mapName, sizeof(mapName));

  if (!(IsMapValid(mapName) || EqualsRandom(mapName))) {
    ReplyToCommand(client, "Invalid map name: %s", mapName);
    return Plugin_Handled;
  }

  Log4All(client, "changed map to %s", mapName);

  if (mapChangeTimer != null) {
    CloseHandle(mapChangeTimer);
  }
  nextMap = mapName;
  mapChangeTimer = CreateTimer(1.0, Timer_ChangeMap, _, TIMER_REPEAT);

  return Plugin_Handled;
}

Action Timer_ChangeMap(Handle timer) {
  static int countDown = ACK_COUNT_DOWN;

  if (countDown <= 0) {
    if (EqualsRandom(nextMap)) {
      ServerCommand("randommap\n");
    } else {
      ForceChangeLevel(nextMap, "player requested level change");
    }
    
    countDown = ACK_COUNT_DOWN;
    mapChangeTimer = null;
    return Plugin_Stop;
  }

  PrintCenterTextAll("map change in %d...", countDown);
  countDown--;
  
  return Plugin_Continue;
}

Action Command_Teleport_Bots(int client, int args) {
  if (client == 0) {
    ReplyToCommand(client, "Only players may execute that command!");
    return Plugin_Handled;
  }

  TeleportBots(client, .log = true);

  return Plugin_Handled;
}

Action Command_Restart(int client, int args) {
  int inSecs = ACK_COUNT_DOWN;
  if (args > 0) {
    if (!GetCmdArgIntEx(1, inSecs)) {
      ReplyToCommand(client, "First argument has to be a whole number of seconds");
      return Plugin_Handled;
    }
  }
  RestartServer(client, inSecs);
  return Plugin_Handled;
}

void RestartServer(int client = -1, int countdown = 0) {
  if (client >= 0) {
    Log4All(client, "Restarted the server");
  }
  float delay = 1.0;
  if (countdown == 0) {
    delay = 0.0;
  }
  CreateTimer(delay, Timer_RestartServer, countdown, TIMER_REPEAT);
}

Action Timer_RestartServer(Handle handle, int inSecs) {
  static int countDown = -1;

  if (countDown < 0) {
    countDown = inSecs;
  }

  if (countDown > 0) {
    PrintCenterTextAll("server restart in %d...", countDown);
    countDown--;
    return Plugin_Continue;
  }

  countDown = -1;

  char currentMap[MAX_MAP_NAME_LENGTH];
  GetCurrentMap(currentMap, sizeof(currentMap));
  ForceChangeLevel(currentMap, "server restart");

  return Plugin_Stop;
}

void TeleportBots(int client, bool log = false, int executer = -1) {
  TFTeam team = TF2_GetClientTeam(client);
  int[] teamClients = new int[MaxClients];
  int teamSize = GetClientsInTeam(team, teamClients, MaxClients);

  float location[3];
  GetClientAbsOrigin(client, location);
  float angle[3];
  GetClientAbsAngles(client, angle);

  for (int i = 0; i < teamSize; i++) {
    int bot = teamClients[i];
    if (IsBot(bot)) {
      TeleportEntity(bot, location, angle);
    }
  }

  if (log) {
    if (executer == -1) {
      executer = client;
    }
    char teamColor[4];
    GetTeamIdentifier(team, teamColor, sizeof(teamColor));
    ToLowercase(teamColor);
    char clientName[MAX_NAME_LENGTH];
    GetClientName(client, clientName, sizeof(clientName));
    Log4All(executer, "Teleported the %s bots to %s", teamColor, clientName);
  }
}

Action Command_Lobby(int client, int args) {
  bool clean = false;
  if (args > 0) {
    char arg[8];
    GetCmdArg(1, arg, sizeof(arg));

    if (strcmp(arg, "clean") == 0) {
      clean = true;
    } else {
      ReplyToCommand(client, "Invalid parameter. Use 'clean' to switch to a clean lobby mode.");
      return Plugin_Handled;
    }
  }
  StartLobbyMode(client, clean);
  return Plugin_Handled;
}

void StartLobbyMode(int client = 0, bool clean = false) {
  if (clean) {
    KickBots();
  }
  fullRoundsPlayed = 0;
  cvarMpTournament.IntValue = 1;
  ServerCommand(RESTART_TOURNAMENT_CMD);
  Log4All(client, "Switched to lobby mode");
}

void KickBots() {
  ServerCommand("tf_bot_kick all\n");
  cvarTfBotQuota.IntValue = 0; //make sure they don't fill up again
}

bool IsLobbyModeActive() {
  return cvarMpTournament.IntValue == 1;
}

Action Timer_LobbyModeInfo(Handle handle) {
  if (IsLobbyModeActive()) {
    PrintHintTextToAll("Lobby mode - ready up to start the round (F4) or use '!st_help' in chat for a command overview");
  }

  return Plugin_Continue;
}

Action Command_Eggseck(int client, int args) {
  char script[16];
  GetCmdArg(1, script, sizeof(script));
  if (strcmp(script, "start") == 0) {
    StartMatch(client);
  } else if (strcmp(script, "pause") == 0) {
    StartLobbyMode(client);
  } else {
    ReplyToCommand(client, "Invalid parameter. Use start or pause.");
  }
  return Plugin_Handled;
}

Action Command_UpdateTeamComp(int client, int args) {
  UpdateTeamComposition();
  Log4All(client, "Updated team composition");
  return Plugin_Handled;
}

Action Command_Difficulty(int client, int args) {
  if (args == 0) {
    ReplyToCommand(client, "Current difficulty is %d/3", cvarTfBotDifficulty.IntValue);
    return Plugin_Handled;
  }

  int newDiff;
  if (!GetCmdArgIntEx(1, newDiff) || newDiff < 0 || newDiff > 3) {
    ReplyToCommand(client, "please enter a whole number between 0 and 3");
    return Plugin_Handled;
  }

  ChangeBotDifficulty(newDiff, false, client);

  ReplyToCommand(client, "The bots need to be reloaded for this to have effect: !st_lobby clean");

  return Plugin_Handled;
}

void ChangeBotDifficulty(int newDifficulty, bool updateBots = true, int executorClient = -1) {
  int oldDiff = cvarTfBotDifficulty.IntValue;
  cvarTfBotDifficulty.IntValue = newDifficulty;

  if (updateBots) {
    KickBots();
    CreateTimer(0.0, Timer_UpdateTeamComp);
  }

  if (executorClient != -1) {
    Log4All(executorClient, "Changed the bot difficulty from %d to %d", oldDiff, newDifficulty);
  }
}

Action Command_Menu(int client, int args) {
  Panel panel = new Panel();

  panel.SetTitle("StepTech quick menu");
  panel.DrawItem("change difficulty");
  panel.DrawItem("teleport bots of your team to you");
  panel.DrawItem("start lobby mode");
  panel.DrawItem("update bot classes");
  panel.DrawItem("restart server");
  panel.DrawItem("exit");

  panel.Send(client, PanelHandler_Menu, 60);

  delete panel;
  return Plugin_Handled;
}

int PanelHandler_Menu(Menu menu, MenuAction action, int client, int selection) {
  if (action == MenuAction_Select) {
    switch (selection) {
      //diff
      case 1: { 
        Panel panel = new Panel();

        panel.SetTitle("What difficulty would you like to play on?");
        panel.DrawItem("easy (0)");
        panel.DrawItem("normal (1)");
        panel.DrawItem("hard (2)");
        panel.DrawItem("expert (3)");
        panel.DrawItem("exit");

        panel.Send(client, PanelHandler_Difficulty, 60);
        delete panel;
      }
      //teleport
      case 2: {
        TeleportBots(client, .log = true);
      }
      //lobby mode
      case 3: {
        StartLobbyMode(client);
      }
      //update team comp
      case 4: {
        UpdateTeamComposition();
        PrintToChat(client, "updated team compositions");
      }
      //restart
      case 5: {
        RestartServer(client, ACK_COUNT_DOWN);
      }
    }
  }
  return 0;
}

int PanelHandler_Difficulty(Menu menu, MenuAction action, int client, int selection) {
  if (action == MenuAction_Select && selection < 5) {
    int difficulty = selection - 1;
    ChangeBotDifficulty(difficulty, true, client);
  }
  return 0;
}

Action Command_NamePoolAdd(int client, int args) {
  if (args == 0) {
    ReplyToCommand(client, "[class name|id]|any [names...]");
    return Plugin_Handled;
  }

  int nameArgIndex = 1;
  int classIndex = ANY_CLASS_INDEX;
  char classId[MAX_CLASS_ID_LENGTH] = "any";

  char classIdArg[MAX_CLASS_ID_LENGTH];
  GetCmdArg(1, classIdArg, sizeof(classIdArg));
  if (strcmp(classIdArg, "any", false) == 0) {
    nameArgIndex++;
  } else {
    for (int i = 0; i < CLASSES_SIZE; i++) {
      char indexStr[1];
      Format(indexStr, sizeof(indexStr), "%d", classes[i].index);
      if (strcmp(classes[i].id, classIdArg, false) == 0 || strcmp(indexStr, classIdArg) == 0) {
        classIndex = classes[i].index;
        strcopy(classId, sizeof(classId), classes[i].id);
        nameArgIndex++;
        break;
      }
    }
  }

  NameSet nameSet;
  for (; nameArgIndex <= args; nameArgIndex++) {
    char name[NP_NAME_SIZE];
    GetCmdArg(nameArgIndex, name, sizeof(name));
    int res = nameSet.Add(name);
    if (res == -1) {
      ReplyToCommand(client, "out of memory: can't add that many names (max %d)", NP_MAX_NAME_SET_SIZE);
      return Plugin_Handled;
    }
    if (res != strlen(name)) {
      ReplyToCommand(client, "name \"%s\" is too long: max %d characters allowed", name, res);
      return Plugin_Handled;
    }
  }

  if (nameSet.size == 0) {
    ReplyToCommand(client, "Provide some names to add!");
    return Plugin_Handled;
  }

  if (!namePool.AddNameSet(classIndex, nameSet)) {
    ReplyToCommand(client, "Can't add nameset: out of memory");
    return Plugin_Handled;
  }

  char[] nameSetStr = new char[nameSet.GetRequiredStrBufSize()];
  nameSet.ToString(nameSetStr);
  ReplyToCommand(client, "Added name-set to %s: %s", classId, nameSetStr);

  return Plugin_Handled;
}

//event handlers

void Event_ReadyUp(Event event, const char[] name, bool dontBroadcast) {
  bool ready = event.GetInt("readystate") != 0;
  int client = event.GetInt("userid");
  TFTeam team = TF2_GetClientTeam(client);
  switch (team) {
    case TFTeam_Red: {
      readyState.redTeamReady = ready;
      LogMessage("updating readystate of red to %b", ready);
    }
    case TFTeam_Blue: {
      readyState.blueTeamReady = ready;
      LogMessage("updating readystate of blue to %b", ready);
    }
  }

  //make sure we are in tournament lobby mode
  if (cvarMpTournament.IntValue != 1) {
    LogMessage("received ready state update outside of tournament mode");
    return;
  }

  if ((readyState.blueTeamReady || isBotOnlyTeam(TFTeam_Blue)) && (readyState.redTeamReady || isBotOnlyTeam(TFTeam_Red))) {
    StartMatch();
  }
}

void StartMatch(int client = 0) {
  cvarMpTournament.SetString("start");
  ServerCommand(RESTART_TOURNAMENT_CMD);
  cvarMpRestartGame.IntValue = 1; //TODO test
  UpdateTeamComposition();
  Log4All(client, "Started the match (on difficulty %d)", cvarTfBotDifficulty.IntValue);
}

void Event_PlayerChangeClass(Event event, const char[] name, bool dontBroadcast) {
  int client = GetClientOfUserId(event.GetInt("userid"));

  if (IsBot(client)) return;
  LogMessage("player class change detected");

  //update team comp a bit later, since client is not always connected
  CreateTimer(0.0, Timer_UpdateTeamComp);
}

Action Timer_UpdateTeamComp(Handle handle) {
  UpdateTeamComposition();
  return Plugin_Stop;
}

void Event_PlayerChangeTeam(Event event, const char[] name, bool dontBroadcast) {
  int client = GetClientOfUserId(event.GetInt("userid"));

  if (IsBot(client)) return;
  LogMessage("player team change detected");

  CreateTimer(0.0, Timer_UpdateTeamComp); //only update after the event
}

void Event_TeamplayRoundWin(Event event, const char[] name, bool dontBroadcast) {
  if (event.GetBool("full_round")) {
    fullRoundsPlayed++;

    if (fullRoundsPlayed >= 2) {
      Log4All(0, "Round over");
      fullRoundsPlayed = 0;

      StartLobbyModeTimed();
    }
  }
}

bool cancelLobbyMode;
int lobbyModeAcks[MAXPLAYERS];
int lobbyModeAcksLen = 0;

void StartLobbyModeTimed() {
  cancelLobbyMode = false;
  lobbyModeAcksLen = 0;
  CreateTimer(1.0, Timer_AutoLobbyMode, _, TIMER_REPEAT);
}

Action Timer_AutoLobbyMode(Handle handle) {
  static int countDown = LOBBY_MODE_COUNT_DOWN;

  if (cancelLobbyMode) {
    countDown = LOBBY_MODE_COUNT_DOWN;
    return Plugin_Stop;
  }

  if (countDown <= 0) {
    StartLobbyMode();
    countDown = LOBBY_MODE_COUNT_DOWN;
    return Plugin_Stop;
  }

  countDown--;

  Panel panel = new Panel();
  char title[100];
  Format(title, sizeof(title), "Round over. Starting lobby mode in %d seconds...", countDown);
  panel.SetTitle(title);
  panel.DrawItem("cancel");
  panel.DrawItem("ok");

  for (int client = 1; client <= MaxClients; client++) {
    if (IsClientInGame(client) && IndexOf(lobbyModeAcks, lobbyModeAcksLen, client) == -1) {
      panel.Send(client, PanelHandler_AutoLobbyMode, 1);
    }
  }

  delete panel;

  return Plugin_Continue;
}

int IndexOf(const int[] arr, int arrLen, int elem) {
  for (int i = 0; i < arrLen; i++) {
    if (arr[i] == elem) {
      return i;
    }
  }
  return -1;
}

int PanelHandler_AutoLobbyMode(Menu menu, MenuAction action, int client, int selection) {
  if (action == MenuAction_Select) {
    if (selection == 1) {
      cancelLobbyMode = true;
      Log4All(client, "Cancelled lobby mode. Continuing match!");
    } else if (selection == 2 && IndexOf(lobbyModeAcks, lobbyModeAcksLen, client) == -1) {
      lobbyModeAcks[lobbyModeAcksLen++] = client;
    }
  }
  return 0;
}

void Event_MpTournamentChange(ConVar cvar, const char[] oldValue, const char[] newValue) {
  if (strcmp(oldValue, newValue) == 0) return; //ignore if the value didn't change

  LogMessage("mp_tournament changed. Resetting ready state.");
  readyState.reset();
}

enum struct ReadyState {
  bool blueTeamReady;
  bool redTeamReady;

  void reset() {
    this.blueTeamReady = false;
    this.redTeamReady = false;
  }
}

void UpdateTeamComposition(TFTeam team = TFTeam_Unassigned, int playersPerTeam = -1, bool updateBotNames = true, TeamCompUpdateSummary summary = {}) {
  if (playersPerTeam < 0) {
    playersPerTeam = cvarTeamSize.IntValue;
  }

  if (team == TFTeam_Unassigned) {
    UpdateTeamComposition(TFTeam_Blue, playersPerTeam, false, summary);
    TeamCompUpdateSummary redSummary;
    UpdateTeamComposition(TFTeam_Red, playersPerTeam, updateBotNames, redSummary);
    summary.added += redSummary.added;
    summary.kicked += redSummary.kicked;

    updateBotQuota(playersPerTeam, summary);

    return;
  }

  char teamName[MAX_TEAM_ID_LENGTH];
  GetTeamIdentifier(team, teamName, sizeof(teamName));
  LogMessage("Updating class composition of team %s", teamName);

  //get prio
  int prioLen = playersPerTeam;
  TFClassType[] prio = new TFClassType[prioLen];
  GetClassPriority(playersPerTeam, prio, prioLen);

  //create optimal composition
  int optComp[COMP_SIZE];
  for (int i = 0; i < prioLen; i++) {
    TFClassType class = prio[i];
    int index = Wrap(class).index;
    optComp[index] += 1;
  }

  //determine current player (not bot) composition
  int playerComp[COMP_SIZE];
  int[] teamClients = new int[MaxClients];
  int teamSize = GetClientsInTeam(team, teamClients, MaxClients);
  for (int i = 0; i < teamSize; i++) {
    int client = teamClients[i];
    if (!IsBot(client)) {
      TFClassType playerClass = TF2_GetPlayerClass(client);
      if (playerClass == TFClass_Unknown) continue;

      int index = Wrap(playerClass).index;
      playerComp[index] += 1;
    }
  }

  //determine target composition
  int targetComp[COMP_SIZE];
  for (int i = 0; i < COMP_SIZE; i++) {
    targetComp[i] = optComp[i] - playerComp[i];
  }

  //account for players stacking more than the optimal composition
  int toRemove = 0;
  for (int i = 0; i < COMP_SIZE; i++) {
    int target = targetComp[i];
    if (target < 0) {
      toRemove -= target; //- since target is negative
    }
  }
  //remove the n lowest priority classes where possible
  if (toRemove > 0) {
    int removed = 0;
    //iterate backwards over the priorities
    for (int i = prioLen - 1; i >= 0; i--) {
      if (removed < toRemove) {
        TFClassType class = prio[i];
        int index = Wrap(class).index;
        if (targetComp[index] > 0) {
          targetComp[index] -= 1;
          removed++;
        }
      }
    }
  }
  
  //throw out bots which overfill the target comp
  int kicked = 0;
  for (int i = 0; i < teamSize; i++) {
    int client = teamClients[i];
    if (IsBot(client)) {
      TFClassType class = TF2_GetPlayerClass(client);
      int index = Wrap(class).index;
      if (targetComp[index] > 0) {
        targetComp[index] -= 1; //bot may stay in that class
      } else {
        //bot may not stay there; remove him
        char botName[MAX_NAME_LENGTH];
        GetClientName(client, botName, sizeof(botName));
        ServerCommand("tf_bot_kick \"%s\"\n", botName);
        kicked += 1;
      }
    }
  }
  LogMessage("Kicked %d bots", kicked);
  summary.kicked = kicked;

  //fill up remaining spots in the target comp
  int added = 0;
  for (int i = 0; i < COMP_SIZE; i++) {
    int target = targetComp[i];
    if (target > 0) {
      ServerCommand("tf_bot_add %d %s %s\n", target, teamName, classes[i].id);
      added += 1;
    }
  }
  LogMessage("Added %d bots", added);
  summary.added = added;

  updateBotQuota(playersPerTeam, summary);

  if (updateBotNames) {
    CreateTimer(1.0, Timer_UpdateBotNames); //update after the bots have been added
  }
}

void updateBotQuota(int players_per_team = -1, const TeamCompUpdateSummary summary = {}) {
  if (players_per_team < 0) {
    players_per_team = cvarTeamSize.IntValue;
  }

  cvarTfBotQuota.IntValue = 2 * players_per_team - GetPlayerCount() + summary.kicked - summary.added;
}

enum struct TeamCompUpdateSummary {
  int added;
  int kicked;
}

Action Timer_UpdateBotNames(Handle handle) {
  UpdateBotNames();
  return Plugin_Stop;
}

void UpdateBotNames() {
  LogMessage("updating bot names");

  int npNumSetsLen = sizeof(namePool.numSets);
  int npSizesStrLen = ArrayBufSize(npNumSetsLen, EBS_int);
  char[] npSizesStr = new char[npSizesStrLen];
  ToStr(npSizesStr, npSizesStrLen, namePool.numSets, npNumSetsLen);
  for (int client = 1; client < MaxClients; client++) {
    if (!IsClientConnected(client)) {
      continue;
    }

    if (!IsBot(client)) {
      continue;
    }

    AssignNamePoolName(client);
  }
}

void AssignNamePoolName(int client) {
  TFClassType class = TF2_GetPlayerClass(client);
  int classIndex = Wrap(class).index;

  NameSet nameSet;
  namePool.GetRandomNameSet(classIndex, nameSet, ANY_CLASS_INDEX);
  for (int i = 0; i < nameSet.size; i++) {
    char name[NP_NAME_SIZE];
    nameSet.Get(i, name, sizeof(name));

    int currentNameHolder = GetClientByName(name);
    if (currentNameHolder == client) {
      return; //client already has a name from the namepool
    }
    if (currentNameHolder > 0) {
      continue; //name is already taken by someone else
    }

    SetClientName(client, name);
    return;
  }
}

void GetClassPriority(int playersPerTeam, TFClassType[] buf, int bufSize) {
  if (playersPerTeam < 1) {
    return;
  }

  TFClassType prio[] = {
    TFClass_Soldier, 
    TFClass_Medic,
    TFClass_DemoMan,
    TFClass_Scout,
    TFClass_Engineer,
    TFClass_Heavy, 
    TFClass_Pyro, 
    TFClass_Spy, 
    TFClass_Sniper
  };

  if (playersPerTeam == 1) {
    prio[0] = TFClass_Scout;
  } 

  for (int i = 0; i < bufSize && i < playersPerTeam; i++) {
    buf[i] = prio[i % sizeof(prio)];
  }
}

int GetTeamIdentifier(TFTeam team, char[] buf, int bufSize) {
  switch (team) {
    case TFTeam_Blue: {
      return strcopy(buf, bufSize, "Blue");
    }
    case TFTeam_Red: {
      return strcopy(buf, bufSize, "Red");
    }
    case TFTeam_Spectator: {
      return strcopy(buf, bufSize, "Spectator");
    }
  }
  return strcopy(buf, bufSize, "Unassigned");
}
