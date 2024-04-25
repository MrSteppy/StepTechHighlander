#define MAX_MAP_NAME_SIZE 64
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
    radius REAL NOT NULL,\
    activationTime REAL NOT NULL,\
    action INTEGER NOT NULL,\
    tLocX REAL,\
    tLocY REAL,\
    tLocZ REAL,\
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
    rule.center[0] = SQL_FetchFloat(preparedStatement, p++);
    rule.center[1] = SQL_FetchFloat(preparedStatement, p++);
    rule.center[2] = SQL_FetchFloat(preparedStatement, p++);
    rule.radius = SQL_FetchFloat(preparedStatement, p++);
    rule.activationTime = SQL_FetchFloat(preparedStatement, p++);
    switch (SQL_FetchInt(preparedStatement, p++)) {
      case 0: {
        rule.action = MapRuleAction_Kill;
      }
      case 1: {
        rule.action = MapRuleAction_Tp;
      }
    }
    rule.targetLocation[0] = SQL_FetchFloat(preparedStatement, p++);
    rule.targetLocation[1] = SQL_FetchFloat(preparedStatement, p++);
    rule.targetLocation[2] = SQL_FetchFloat(preparedStatement, p++);
    SQL_FetchString(preparedStatement, p++, rule.description, sizeof(rule.description));

    AddMapRuleToCache(rule);
  }

  delete preparedStatement;

  LogMessage("Loaded %d map rules for map %s", activeMapRulesLen, mapBuf);
}

/**
 * Adds a MapRule to the db and also to the active map rules if the current map matches. Updates the maprules id. 
 */
void AddMapRule(MapRule rule) {
  static DBStatement addWithTpStatement = null;
  if (addWithTpStatement == null) {
    if ((addWithTpStatement = SQL_PrepareQuery(db, "INSERT INTO mapRules (map, rangeMin, rangeMax, locationX, locationY, locationZ, radius, activationTime, action, tpLocX, tpLocY, tpLocZ, description) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?)", error, ERROR_SIZE)) == INVALID_HANDLE) {
      LogSQLError("Failed to prepare statement to add map rule with tp to db");
      addWithTpStatement = null;
      return;
    }
  }
  static DBStatement addWithKillStatement = null;
  if (addWithKillStatement == null) {
    if ((addWithKillStatement = SQL_PrepareQuery(db, "INSERT INTO mapRules (map, rangeMin, rangeMax, locationX, locationY, locationZ, radius, activationTime, action, description) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?)", error, ERROR_SIZE)) == INVALID_HANDLE) {
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
      ThrowError("unexpected rule action: %d", rule.action);
    }
  }

  int p = 0;
  SQL_BindParamString(addStatement, p++, rule.map, false);
  SQL_BindParamInt(addStatement, p++, rule.scoreRange.start);
  SQL_BindParamInt(addStatement, p++, rule.scoreRange.end);
  SQL_BindParamFloat(addStatement, p++, rule.center[0]);
  SQL_BindParamFloat(addStatement, p++, rule.center[1]);
  SQL_BindParamFloat(addStatement, p++, rule.center[2]);
  SQL_BindParamFloat(addStatement, p++, rule.radius);
  SQL_BindParamFloat(addStatement, p++, rule.activationTime);
  switch (rule.action) {
    case MapRuleAction_Tp: {
      SQL_BindParamFloat(addStatement, p++, rule.targetLocation[0]);
      SQL_BindParamFloat(addStatement, p++, rule.targetLocation[1]);
      SQL_BindParamFloat(addStatement, p++, rule.targetLocation[2]);
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
    if ((preparedStatement = SQL_PrepareQuery(db, "DELETE FROM mapRules WHERE id = ?", error, ERROR_SIZE)) == INVALID_HANDLE) {
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
  float center[3];
  float radius;
  float activationTime;
  MapRuleAction action;
  float targetLocation[3];
  char description[MAX_DESCRIPTION_SIZE];

  bool appliesTo(int client) {
    float location[3];
    GetClientAbsOrigin(client, location);

    float dx = this.center[0] - location[0];
    float dz = this.center[2] - location[2];

    float distanceFromCenterSquared = dx * dx + dz * dz;
    float yMin = this.center[1] - this.radius;
    float yMax = this.center[1] + 2 * this.radius;
    float y = location[1];

    return distanceFromCenterSquared <= this.radius * this.radius && yMin <= y && y <= yMax;
  }
}
