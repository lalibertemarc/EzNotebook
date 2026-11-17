std = "lua51"
max_line_length = false
self = false
exclude_files = { ".release/", "tests/" }

globals = {
    "EzNotebookDB",
    "EzNotebookCharDB",
    "EzNotebook_Toggle",
    "EzNotebook_AddTask",
    "BINDING_HEADER_EZNOTEBOOK",
    "BINDING_NAME_EZNOTEBOOK_TOGGLE",
    "BINDING_NAME_EZNOTEBOOK_ADD",
    "SLASH_EZNOTEBOOK1",
    "SLASH_EZNOTEBOOK2",
    "SLASH_EZNOTEBOOKTODO1",
    "SlashCmdList",
    "UISpecialFrames",
}

read_globals = {
    -- Lua / WoW utility
    "date", "time", "tinsert", "issecretvalue", "hooksecurefunc", "GetTime", "GetBuildInfo",
    -- Frames & UI
    "CreateFrame", "UIParent", "ChatFrame1", "DEFAULT_CHAT_FRAME", "GameTooltip", "ItemRefTooltip",
    "GetCursorPosition", "GetCursorInfo", "ClearCursor", "IsModifiedClick",
    "ChatFrameUtil", "ChatEdit_InsertLink", "Minimap", "GetMinimapShape", "AddonCompartmentFrame",
    -- Namespaced APIs
    "C_DateAndTime", "C_QuestLog", "C_Item", "C_Map", "C_SuperTrack", "C_Timer", "C_Spell", "UiMapPoint",
    -- Global APIs
    "GetQuestResetTime", "IsQuestFlaggedCompleted", "GetQuestLogIndexByID", "GetItemCount", "GetSpellLink",
    "GetNumQuestLogEntries", "GetQuestLogTitle", "GetQuestLink", "GetRealZoneText", "GetZoneText",
    "GetSubZoneText", "IsInInstance", "GetInstanceInfo", "UnitIsDeadOrGhost", "UnitLevel", "UnitGUID", "UnitName",
}
