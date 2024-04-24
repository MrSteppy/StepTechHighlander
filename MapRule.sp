#define MAX_MAP_NAME_SIZE 64
#define MAP_RULE_RADIUS 180.0 //value in hammer units
#define MAX_MAP_RULES 32
#define ERROR_SIZE 255
#define MAX_DESCRIPTION_SIZE 255

#define DATABASE_NAME "st_mapRules"

Database db;
MapRule activeMapRules[MAX_MAP_RULES];
int activeMapRulesLen = 0;
char error[ERROR_SIZE];

void LogSQLError(const char[] detailMessage, any ...) {
  if (strlen(error) == 0) {
    SQL_GetError(db, error, ERROR_SIZE);
  }
  char detailBuf[255];
  VFormat(detailBuf, sizeof(detailBuf), detailMessage, 2);
  PrintToServer("[ERROR] %s: %s", detailBuf, error);
  LogError("%s: %s", detailBuf, error);
  error = ""; //clear the error, so we don't accidentally log it again
}

void InitDB() {
  if (db != null) {
    delete db;
  }

  db = SQLite_UseDatabase(DATABASE_NAME, error, ERROR_SIZE);
  if (db == INVALID_HANDLE) {
    LogSQLError("Failed to connect to database");
    db = null;
    return;
  }

  if (!SQL_FastQuery(db, "CREATE TABLE IF NOT EXISTS mapRules (\
    id INTEGER PRIMARY KEY,\
    map TEXT NOT NULL,\
    rangeMin INTEGER NOT NULL,\
    rangeMax INTEGER NOT NULL,\ 
    locationX REAL NOT NULL,\
    locationY REAL NOT NULL,\
    locationZ REAL NOT NULL,\
    action INTEGER NOT NULL,\
    tpLocX REAL,\
    tpLocY REAL,\
    tpLocZ REAL,\
    description TEXT NOT NULL\
    )")) {
    LogSQLError("Failed to create table");
  }
}

void LoadMapRules(const char[] map = "") {
  char mapBuf[MAX_MAP_NAME_SIZE];
  if (strlen(map) == 0) {
    GetCurrentMap(mapBuf, sizeof(mapBuf));
  } else {
    strcopy(mapBuf, sizeof(mapBuf), map);
  }

  if (db == null) {
    InitDB();
  }

  activeMapRulesLen = 0;
  
  static DBStatement preparedStatement = null;
  if (preparedStatement == null) {
    if ((preparedStatement = SQL_PrepareQuery(db, "SELECT * FROM mapRules WHERE map = ?", error, ERROR_SIZE)) == INVALID_HANDLE) {
      LogSQLError("failed to prepare statement to fetch map rules");
      return;
    }
  }
  SQL_BindParamString(preparedStatement, 0, mapBuf, false);
  if (!SQL_Execute(preparedStatement)) {
    LogSQLError("Failed to query map rules for map '%s'", mapBuf);
    return;
  }

  while (SQL_FetchRow(preparedStatement)) {
    MapRule rule;

    int p = 0;
    rule.id = SQL_FetchInt(preparedStatement, p++);
    SQL_FetchString(preparedStatement, p++, rule.map, sizeof(rule.map));
    rule.scoreRange.start = SQL_FetchInt(preparedStatement, p++);
    rule.scoreRange.end = SQL_FetchInt(preparedStatement, p++);
    rule.location[0] = SQL_FetchFloat(preparedStatement, p++);
    rule.location[1] = SQL_FetchFloat(preparedStatement, p++);
    rule.location[2] = SQL_FetchFloat(preparedStatement, p++);
    switch (SQL_FetchInt(preparedStatement, p++)) {
      case 0: {
        rule.action = MapRuleAction_Kill;
      }
      case 1: {
        rule.action = MapRuleAction_Tp;
      }
    }
    rule.teleportLocation[0] = SQL_FetchFloat(preparedStatement, p++);
    rule.teleportLocation[1] = SQL_FetchFloat(preparedStatement, p++);
    rule.teleportLocation[2] = SQL_FetchFloat(preparedStatement, p++);
    SQL_FetchString(preparedStatement, p++, rule.description, sizeof(rule.description));

    AddMapRuleToCache(rule);
  }

  delete preparedStatement;

  PrintToServer("Loaded %d map rules for map %s", activeMapRulesLen, mapBuf);
}

/**
 * Adds a MapRule to the db and also to the active map rules if the current map matches. Updates the maprules id. 
 */
void AddMapRule(MapRule rule) {
  static DBStatement addWithTpStatement = null;
  if (addWithTpStatement == null) {
    if ((addWithTpStatement = SQL_PrepareQuery(db, "INSERT INTO mapRules (map, rangeMin, rangeMax, locationX, locationY, locationZ, action, tpLocX, tpLocY, tpLocZ, description) VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?)", error, ERROR_SIZE)) == INVALID_HANDLE) {
      LogSQLError("Failed to prepare statement to add map rule with tp to db");
      addWithTpStatement = null;
      return;
    }
  }
  static DBStatement addWithKillStatement = null;
  if (addWithKillStatement == null) {
    if ((addWithKillStatement = SQL_PrepareQuery(db, "INSERT INTO mapRules (map, rangeMin, rangeMax, locationX, locationY, locationZ, action, description) VALUES (?, ?, ?, ?, ?, ?, 0, ?)", error, ERROR_SIZE)) == INVALID_HANDLE) {
      LogSQLError("Failed to prepare statement to add map rule with kill to db");
      addWithKillStatement = null;
      return;
    }
  }
  static DBStatement fetchIdStatement = null;
  if (fetchIdStatement == null) {
    if ((fetchIdStatement = SQL_PrepareQuery(db, "SELECT id FROM mapRules ORDER BY id DESC LIMIT 1", error, ERROR_SIZE)) == INVALID_HANDLE) {
      LogSQLError("Failed to prepare statement to fetch added map rule id");
      fetchIdStatement = null;
      return;
    }
  }

  DBStatement addStatement;
  switch (rule.action) {
    case MapRuleAction_Kill: {
      addStatement = addWithKillStatement;
    }
    case MapRuleAction_Tp: {
      addStatement = addWithTpStatement;
    }
    default: {
      ThrowError("unexpected action: %d", rule.action);
    }
  }

  int p = 0;
  SQL_BindParamString(addStatement, p++, rule.map, false);
  SQL_BindParamInt(addStatement, p++, rule.scoreRange.start);
  SQL_BindParamInt(addStatement, p++, rule.scoreRange.end);
  SQL_BindParamFloat(addStatement, p++, rule.location[0]);
  SQL_BindParamFloat(addStatement, p++, rule.location[1]);
  SQL_BindParamFloat(addStatement, p++, rule.location[2]);
  switch (rule.action) {
    case MapRuleAction_Tp: {
      SQL_BindParamFloat(addStatement, p++, rule.teleportLocation[0]);
      SQL_BindParamFloat(addStatement, p++, rule.teleportLocation[1]);
      SQL_BindParamFloat(addStatement, p++, rule.teleportLocation[2]);
    }
  }
  SQL_BindParamString(addStatement, p++, rule.description, false);

  if (!SQL_Execute(addStatement)) {
    LogSQLError("failed to add map rule to db");
    return;
  }

  if (!SQL_Execute(fetchIdStatement)) {
    LogSQLError("failed to retrieve id of added map rule");
    return;
  }

  SQL_FetchRow(fetchIdStatement);
  rule.id = SQL_FetchInt(fetchIdStatement, 0);
  
  //add to active rules
  char currentMap[MAX_MAP_NAME_SIZE];
  GetCurrentMap(currentMap, sizeof(currentMap));
  if (strcmp(rule.map, currentMap) == 0) {
    AddMapRuleToCache(rule);
  }
}

void DeleteMapRule(int id) {
  static DBStatement preparedStatement = null;
  if (preparedStatement == null) {
    if ((preparedStatement = SQL_PrepareQuery(db, "DELETE FROM mapRules WHERE id = ?", error, ERROR_SIZE))) {
      LogSQLError("Failed to prepare statement to delete map rule");
      preparedStatement = null;
      return;
    }
  }
  SQL_BindParamInt(preparedStatement, 0, id);
  if (!SQL_Execute(preparedStatement)) {
    LogSQLError("Failed to delete map rule with id %d from db", id);
    return;
  }

  int a = 0;
  for (int i = 0; i < activeMapRulesLen; i++) {
    MapRule rule;
    rule = activeMapRules[i];
    if (rule.id != id) {
      activeMapRules[a++] = rule;
    }
  }
  activeMapRulesLen = a;
}

void AddMapRuleToCache(const MapRule rule) {
  if (activeMapRulesLen < MAX_MAP_RULES) {
    activeMapRules[activeMapRulesLen++] = rule;
  } else {
    ThrowError("Can't add another map rule (out of memory)");
  }
}

enum struct Range {
  int start;
  int end;

  bool contains(int i) {
    return this.start <= i && i <= this.end;
  }
}

enum MapRuleAction {
  MapRuleAction_Kill,
  MapRuleAction_Tp,
}

enum struct MapRule {
  int id;
  char map[MAX_MAP_NAME_SIZE];
  Range scoreRange;
  float location[3];
  MapRuleAction action;
  float teleportLocation[3];
  char description[MAX_DESCRIPTION_SIZE];

  bool appliesTo(int client) {
    float location[3];
    GetClientAbsOrigin(client, location);
    float distSquared = GetDistanceSquared(location, this.location);

    return distSquared <= MAP_RULE_RADIUS * MAP_RULE_RADIUS;
  }
}

float GetDistanceSquared(const float locationA[3], const float locationB[3]) {
  float x = locationA[0] - locationB[0];
  float y = locationA[1] - locationB[1];
  float z = locationA[2] - locationB[2];

  return x * x + y * y + z * z;
}
