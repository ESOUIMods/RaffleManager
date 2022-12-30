local internal = _G["LibGuildStore_Internal"]

local ADDON_NAME = "RaffleManager"
local ADDON_VERSION = "5.0.3"
local SAVEDVARS_NAME = "RaffleManager_SavedVariables"
local SAVEDVARS_VERSION = 1

local TICKET_COST = 1000

local RAFFLEMANAGER_DEBUG = true
local RAFFLEMANAGER_ACTIVE = false
local RAFFLEMANAGER_PAUSED = false

local RAFFLEMANAGER_WINDOW = nil
local RAFFLEMANAGER_COMPOSE = nil
local RAFFLEMANAGER_CONFIRM = nil
local RAFFLEMANAGER_INBOX = nil
local RAFFLEMANAGER_SENT = nil

local CONFIRM_SORT_KEYS = {
  ["id"] = { isNumeric = true },
  ["name"] = { tiebreaker = "id" },
  ["tickets"] = { tiebreaker = "id", isNumeric = true },
  ["barter"] = { tiebreaker = "id", isNumeric = true },
  ["mail"] = { tiebreaker = "id" },
  ["rankIndex"] = { tiebreaker = "id", isNumeric = true }
}

-- Local Variables

local RaffleManagerWindow = ZO_Object:Subclass()
local RaffleManagerExport = ZO_Object:Subclass()
local RaffleManagerConfirm = ZO_SortFilterList:Subclass()
local RaffleManagerMessage = ZO_Object:Subclass()

local origPlayerContextMenu = nil

local Guilds = {
  ["GuildNames"] = { },
  ["GuildRanks"] = { },
  ["GuildMembers"] = { }
}

local SELECTED_GUILD = nil
local SELECTED_DAY = nil

local GuildChoice = {}
local CurrentMail = {}
local PendingMail = {}

local lastKnownRecipient = nil
local mailBoxOpen = false
local progressBarTotal = 0
local progressBarUnit = 0
local sentMailCount = 0
local recipientID = 0
local throttleTimer = 2000

local DefaultVars = {}
local SavedVars

-- Menu Buttons

local menuBarButtons = {
  {
    categoryName = SI_RAFFLEMANAGER_TITLE_EXPORT,
    descriptor = "RaffleManagerExport",
    normal = "esoui/art/bank/bank_tabicon_deposit_up.dds",
    pressed = "esoui/art/bank/bank_tabicon_deposit_down.dds",
    highlight = "esoui/art/bank/bank_tabicon_deposit_over.dds",
  },
  {
    categoryName = SI_RAFFLEMANAGER_TITLE_MESSAGE,
    descriptor = "RaffleManagerMessage",
    normal = "esoui/art/mail/mail_tabicon_compose_up.dds",
    pressed = "esoui/art/mail/mail_tabicon_compose_down.dds",
    highlight = "esoui/art/mail/mail_tabicon_compose_over.dds",
  },
  {
    categoryName = SI_RAFFLEMANAGER_TITLE_CONFIRM,
    descriptor = "RaffleManagerConfirm",
    normal = "esoui/art/contacts/tabicon_friends_up.dds",
    pressed = "esoui/art/contacts/tabicon_friends_down.dds",
    highlight = "esoui/art/contacts/tabicon_friends_over.dds",
  },
}

---
-- Non UI shit
---

local LOADING_EVENTS = false

function RaffleManager_ParseRoster()
  if SELECTED_GUILD == nil then
    CHAT_SYSTEM:AddMessage("Select a guild before exporting!")
    return
  end

  local gnum = GuildChoice[SELECTED_GUILD]

  local gname = GetGuildName(gnum)

  if not MasterMerchant or not internal.guildSales or not internal.guildSales[gname] or not internal.guildSales[gname].sellers then
    CHAT_SYSTEM:AddMessage("Need MasterMerchant to export data!")
    return
  end

  local data = {}

  for i = 1, GetNumGuildMembers(gnum) do
    local account, note, rankindex, _ = GetGuildMemberInfo(gnum, i)

    local rank_name = GetGuildRankCustomName(gnum, rankindex)

    local line = { ["account"] = account, sales30 = 0, sales10 = 0, purchases30 = 0, purchases10 = 0, joined = 0, rank = rank_name }

    local mmd = internal.guildSales[gname].sellers
    local mmp = internal.guildPurchases[gname].sellers
    if not mmd[account] and not mmp[account] then
      CHAT_SYSTEM:AddMessage("Skipping " .. account .. " as no MasterMerchant data.")
    else
      mmp = mmp[account]
      mmd = mmd[account]
      if not mmd or not mmd.sales then
        CHAT_SYSTEM:AddMessage("No sales for " .. account)
      else
        line.sales30 = mmd.sales[MM_DATERANGE_30DAY]
        if line.sales30 == nil then line.sales30 = 0 end
        line.sales10 = mmd.sales[MM_DATERANGE_10DAY]
        if line.sales10 == nil then line.sales10 = 0 end
      end

      if not mmp or not mmp.sales then
        CHAT_SYSTEM:AddMessage("No purchases for " .. account)
      else
        line.purchases30 = mmp.sales[MM_DATERANGE_30DAY]
        line.purchases10 = mmp.sales[MM_DATERANGE_10DAY]
        if line.purchases30 == nil then line.purchases30 = 0 end
        if line.purchases10 == nil then line.purchases10 = 0 end
      end
    end

    if AMT ~= nil and AMT.savedData ~= nil and AMT.savedData[gname] ~= nil then
      local r = account:lower()
      if AMT.savedData[gname][r] ~= nil then
        local v = AMT.savedData[gname][r].timeJoined
        line.joined = v
      end
    end

    table.insert(data, line)
  end

  SavedVars.roster_timestamp = GetTimeStamp()
  SavedVars.roster_data = data
end

function RaffleManager_FreeTickets()
  if SELECTED_GUILD == nil then
    CHAT_SYSTEM:AddMessage("Select a guild before exporting!")
    return
  end

  local gnum = GuildChoice[SELECTED_GUILD]

  local gname = GetGuildName(gnum)

  local data = {}

  for i = 1, GetNumGuildMembers(gnum) do
    local account, _, _, _ = GetGuildMemberInfo(gnum, i)
    table.insert(data, { user = account .. "_free", amount = 1000, timestamp = GetTimeStamp(), id = "free_tickets_50th_" .. math.random(), subject = "FREE TICKETS" })

  end

  SavedVars.mail_data = data
  SavedVars.timestamp = GetTimeStamp()
end

function RaffleManager_Local()
  if SELECTED_GUILD == nil then
    CHAT_SYSTEM:AddMessage("Select a guild before exporting!")
    return
  end

  local gnum = GuildChoice[SELECTED_GUILD]

  local gname = GetGuildName(gnum)

  local data = {}

  for i = 1, GetNumGuildMembers(gnum) do
    local account, _, _, _ = GetGuildMemberInfo(gnum, i) -- 3

    local line = { user = account .. "_free", amount = 0, timestamp = GetTimeStamp(), id = "buy_local_" .. math.random(), subject = "BUY LOCAL TICKETS" }

    local mmd = internal.guildSales[gname].sellers
    local mmp = internal.guildPurchases[gname].sellers
    if not mmd[account] and not mmp[account] then
      CHAT_SYSTEM:AddMessage("Skipping " .. account .. " as no MasterMerchant data.")
    else
      local total = 0

      mmp = mmp[account]
      mmd = mmd[account]
      if not mmd or not mmd.sales then
      elseif mmd.sales and mmd.sales[MM_DATERANGE_THISWEEK] ~= nil then
        total = total + mmd.sales[MM_DATERANGE_THISWEEK]
      end

      if not mmp or not mmp.sales then
      elseif mmp.sales and mmp.sales[MM_DATERANGE_THISWEEK] ~= nil then
        total = total + mmp.sales[MM_DATERANGE_THISWEEK]
      end

      if total ~= 0 then
        total = math.floor((total + 500) / 1000) * 1000

        if total == 0 then total = 1000 end

        line.amount = total

        table.insert(data, line)
      end
    end

  end

  SavedVars.mail_data = data
  SavedVars.timestamp = GetTimeStamp()
end

function RaffleManager_ParseMail()
  local events = {}

  for i in ZO_GetNextMailIdIter do
    local senderDisplayName, senderCharacterName, subject, icon, unread, fromSystem, fromCS, returned, numAttachments, attachedMoney, codAmount, expiresInDays, secsSinceReceived = GetMailItemInfo(i)
    if attachedMoney ~= 0 and not returned and not fromCS and not fromSystem and subject ~= "Item Sold" and (attachedMoney % TICKET_COST == 0) then
      table.insert(events, { user = senderDisplayName, subject = subject, amount = attachedMoney, id = Id64ToString(i) })
    end
  end

  SavedVars.mail_data = events
  SavedVars.timestamp = GetTimeStamp()

  CHAT_SYSTEM:AddMessage(#events .. " mail events stored. Reload your UI to updated SavedVariables.")
end

function RaffleManager_ParseBank ()
  if SELECTED_GUILD == nil then
    CHAT_SYSTEM:AddMessage("Select a guild before exporting!")
    return
  end

  if LOADING_EVENTS then
    CHAT_SYSTEM:AddMessage("Still loading events!")
    return
  end

  gnum = GuildChoice[SELECTED_GUILD]
  return _RaffleManager_ParseBank(gnum)
end

function _RaffleManager_ParseBank (gnum)
  local num_events = GetNumGuildEvents(gnum, GUILD_HISTORY_BANK)

  --[[Replace with LibHistorie
  while RequestGuildHistoryCategoryNewest(gnum, GUILD_HISTORY_BANK) do
  end
  --]]

  CHAT_SYSTEM:AddMessage("(Not Active or Updated) ; Parsing " .. num_events .. " bank events for tickets.")

  local events = {}

  if SELECTED_DAY == nil then
    SELECTED_DAY = "3"
  end

  local ten_days = 60 * 60 * 24 * tonumber(SELECTED_DAY)

  --[[Replace with LibHistorie
  for i = 1, num_events do
      local etype, secs, par1, par2, par3, par4, par5, par6 = GetGuildEventInfo(gnum, GUILD_HISTORY_BANK, i)
      if etype == GUILD_EVENT_BANKGOLD_ADDED and secs < ten_days and (par2 % TICKET_COST == 0) then
          local user = par1
          local amount = par2
          local _ts = GetTimeStamp() - secs
          local uniq_id = Id64ToString(GetGuildEventId(gnum, GUILD_HISTORY_BANK, i))
          table.insert(events, { user = user, amount = amount, timestamp = _ts, id = uniq_id})
      end
  end

  table.sort(events, function (k1, k2) return k1.timestamp > k2.timestamp end)
  --]]

  SavedVars.timestamp = GetTimeStamp()
  SavedVars.bank_data = events

  CHAT_SYSTEM:AddMessage(#events .. " bank events stored. Reload your UI to updated SavedVariables.")
end

-------------------------------------------------------------------------------
-- TEXT HANDLERS
-------------------------------------------------------------------------------

-- Char Counter

local function CharCounter(str)
  if not str then return 0 end
  local count = 0
  for i = 1, #str do
    if string.byte(str, i) then
      count = count + 1
    end
  end
  return count
end

-- Convert Color

local function hex2rgb(hex)
  hex = hex:gsub("#", "")
  return tonumber("0x" .. hex:sub(1, 2), 16) / 255, tonumber("0x" .. hex:sub(3, 4), 16) / 255, tonumber("0x" .. hex:sub(5, 6), 16) / 255
end

-------------------------------------------------------------------------------
-- CONTROL WINDOW
-------------------------------------------------------------------------------

function RaffleManagerWindow:New(control)
  local manager = ZO_Object.New(self)

  manager.control = control
  manager.menuBar = GetControl(control, "MenuBar")
  manager.menuBarLabel = GetControl(control, "MenuBarLabel")
  manager.body = GetControl(control, "Body")
  manager.visible = false
  manager.activeTab = "RaffleManagerExport"
  manager.labels = {}
  manager.tabs = {}

  for _, buttonData in ipairs(menuBarButtons) do

    buttonData.callback = function() manager:SetTab(buttonData.descriptor) end
    ZO_MenuBar_AddButton(manager.menuBar, buttonData)
    ZO_MenuBar_SetDescriptorEnabled(manager.menuBar, buttonData.descriptor, true)
    manager.labels[buttonData.descriptor] = GetString(buttonData.categoryName)
    manager.tabs[buttonData.descriptor] = CreateControlFromVirtual(buttonData.descriptor, manager.body, buttonData.descriptor)
  end

  ZO_MenuBar_SelectDescriptor(manager.menuBar, manager.activeTab)

  return manager
end

-- Window Tab Handlers

function RaffleManagerWindow:SetTab(tabName)
  self.menuBarLabel:SetText(self.labels[tabName])
  self.menuBarLabel:SetAnchor(TOPRIGHT, RaffleManagerWindowMenuBar, TOPRIGHT, -170, 4)
  self.menuBarLabel:SetFont("ZoFontWinH3")
  self.tabs[self.activeTab]:SetHidden(true)
  self.tabs[tabName]:SetHidden(false)
  self.activeTab = tabName
end

function RaffleManagerWindow:ShowTab(tabName, skipSound)
  if (not self.visible) then
    self.visible = true
    self.control:SetHidden(false)
    SCENE_MANAGER:SetInUIMode(true)
    if (not skipSound) then PlaySound(SOUNDS.SYSTEM_WINDOW_OPEN) end
  end

  if (self.activeTab ~= tabName) then
    if (not ZO_MenuBar_SelectDescriptor(self.menuBar, tabName, true)) then
      if (RAFFLEMANAGER_DEBUG) then d("MenuBar Error: activeTab ~= tabName. Selected 1st visible tab.") end
      ZO_MenuBar_SelectFirstVisibleButton(self.menuBar, true)
    end
  end
end

function RaffleManagerWindow:Toggle()
  if (self.visible) then
    self:Hide()
  else
    self:ShowTab(self.activeTab)
  end
end

function RaffleManagerWindow:ToggleTab(tabName)
  if (self.visible and self.activeTab == tabName) then
    self:Hide()
  else
    self:ShowTab(tabName)
  end
end

function RaffleManagerWindow:Hide()
  if (self.visible) then
    self.visible = false
    self.control:SetHidden(true)
    SCENE_MANAGER:SetInUIMode(false)
    PlaySound(SOUNDS.SYSTEM_WINDOW_CLOSE)
  end
end

-------------------------------------------------------------------------------
-- CONTROL RECIPIENTS
-------------------------------------------------------------------------------

function RaffleManagerConfirm:New(control)
  local manager = ZO_SortFilterList.New(self, control)

  ZO_ScrollList_AddDataType(manager.list, 1, "RaffleManagerConfirmRow", 30, function(control, data) manager:SetupRow(control, data) end)
  ZO_ScrollList_EnableHighlight(manager.list, "ZO_ThinListHighlight")

  manager:SetAlternateRowBackgrounds(true)

  manager.control = control
  manager.masterList = {}
  manager.sortHeaderGroup:SelectHeaderByKey("id")

  return manager
end

function RaffleManagerConfirm:SetupRow(control, data)
  ZO_SortFilterList.SetupRow(self, control, data)

  control:SetHandler("OnMouseUp", function(control, button, upInside, linkText) self:OnRowMouseUp(control, button, upInside, linkText) end)

  local playerLink = ("|H0:display:%s|h%s|h"):format(data.name, data.name)
  GetControl(control, "ID"):SetText(data.id)
  GetControl(control, "Name"):SetText(playerLink)
  GetControl(control, "Tickets"):SetText(data.tickets)
  GetControl(control, "Barter"):SetText(data.barter)
  GetControl(control, "Mail"):SetText(data.mail)

  GetControl(control, "ID"):SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
end

function RaffleManagerConfirm:BuildMasterList()
  ZO_ClearNumericallyIndexedTable(self.masterList)

  for _, data in ipairs(Guilds.GuildMembers) do
    table.insert(self.masterList, data)
  end
end

function RaffleManagerConfirm:FilterScrollList()
  local scrollData = ZO_ScrollList_GetDataList(self.list)
  ZO_ClearNumericallyIndexedTable(scrollData)

  for i = 1, #self.masterList do
    local data = self.masterList[i]
    if data.mail ~= false then
      table.insert(scrollData, ZO_ScrollList_CreateDataEntry(1, data))
    else end
  end
end

function RaffleManagerConfirm:CompareRows(listEntry1, listEntry2)
  return ZO_TableOrderingFunction(listEntry1.data, listEntry2.data, self.currentSortKey, CONFIRM_SORT_KEYS, self.currentSortOrder)
end

function RaffleManagerConfirm:SortScrollList()
  local scrollData = ZO_ScrollList_GetDataList(self.list)

  table.sort(scrollData, function(listEntry1, listEntry2) return self:CompareRows(listEntry1, listEntry2) end)
end

function RaffleManagerConfirm:ColorRow(control, data, mouseIsOver)

end

function RaffleManagerConfirm:OnRowMouseUp(control, button, upInside, linkText)
  if (button == 2 and linkText) then
    if (not self.unlockSelectionCallback) then self.unlockSelectionCallback = function() self:UnlockSelection() end end
    SetMenuHiddenCallback(self.unlockSelectionCallback)
    self:LockSelection()
  end
end

-------------------------------------------------------------------------------
-- CONTROL COMPOSE
-------------------------------------------------------------------------------

function RaffleManagerExport:New(control)
  local manager = ZO_Object.New(self)
  manager.control = control

  manager.guildList = ZO_ComboBox_ObjectFromContainer(GetControl(control, "GuildDropdown"))
  manager.guildList:SetSortsItems(false)
  manager.guildList:SetSpacing(4)
  manager.guildList:ClearItems()

  manager.dayList = ZO_ComboBox_ObjectFromContainer(GetControl(control, "DaysDropdown"))
  manager.dayList:SetSortsItems(false)
  manager.dayList:SetSpacing(4)
  manager.dayList:ClearItems()

  manager.confirmations = control:GetNamedChild("ImportField")
  manager.confirmations:SetMaxInputChars(2000)

  local function OnGuildSelected (_, name, choice)
    SELECTED_GUILD = name
  end

  local function OnDaySelected (_, day, choice)
    SELECTED_DAY = day
  end

  for day = 1, 10 do
    entry = manager.dayList:CreateItemEntry(tostring(day), OnDaySelected)
    manager.dayList:AddItem(entry)
  end

  for guildIndex = 1, GetNumGuilds() do
    guildId = GetGuildId(guildIndex)
    guildName = GetGuildName(guildId)
    GuildChoice[guildName] = guildId

    entry = manager.guildList:CreateItemEntry(guildName, OnGuildSelected) -- Populate guild dropdown box
    manager.guildList:AddItem(entry)
  end
end

local TICKET_LOOKUP = {}
local BARTER_LOOKUP = {}

local OGS = nil

function RaffleManagerMessage:New(control)
  local manager = ZO_Object.New(self)
  manager.control = control

  manager.subject = control:GetNamedChild("SubjectField")
  manager.subject:SetText("(No subject)")
  manager.subject:SetMaxInputChars(MAIL_MAX_SUBJECT_CHARACTERS)

  manager.guildList = ZO_ComboBox_ObjectFromContainer(GetControl(control, "GuildDropdown"))
  manager.guildList:SetSortsItems(false) -- Don't sort list alphabetically
  manager.guildList:SetSpacing(4)
  manager.guildList:ClearItems()

  manager.body = control:GetNamedChild("BodyField")
  manager.body:SetMaxInputChars(MAIL_MAX_BODY_CHARACTERS)

  local guildName, guildChoiceID

  local function OnGuildSelected (_, guildChoice, choice)
    RaffleManagerConfirmLastRecipient:SetText("")
    RaffleManagerConfirmProgressBar:SetDimensions(0, 24)
    RaffleManagerConfirmCancelProgressBar:SetDimensions(0, 24)

    Guilds.GuildMembers = {}
    CurrentMail["recipients"] = {}
    TICKET_LOOKUP = {}
    BARTER_LOOKUP = {}

    progressBarTotal = 0
    progressBarUnit = 0
    sentMailCount = 0
    recipientID = 1

    guildChoiceID = GuildChoice[guildChoice] -- Set selected guild ID

    for numGuildMembers = 1, GetNumGuildMembers(guildChoiceID) do
      local name, note, rankIndex, playerStatus, secsSinceLogoff = GetGuildMemberInfo(guildChoiceID, numGuildMembers)

      if #TICKET_LIST >= 1 then
        for ti = 1, #TICKET_LIST do
          local n, tickets, barter = unpack(TICKET_LIST[ti])
          if tickets == nil then tickets = 0 end
          if barter == nil then barter = 0 end
          n = n:gsub("%p", "%%%1")
          if name:match("^@" .. n .. "$") ~= nil then
            TICKET_LOOKUP[name] = tickets
            BARTER_LOOKUP[name] = barter
            table.insert(Guilds.GuildMembers, { id = 0, name = name, mail = true, tickets = tickets, barter = barter }) -- Populate guild members table
            break
          end
        end
      end
    end

    for k, v in ipairs(Guilds.GuildMembers) do
      if v["mail"] == true then
        v["mail"] = "|c3A92FFPending"
        v["id"] = recipientID
        recipientID = recipientID + 1
        table.insert(CurrentMail["recipients"], v["name"]) -- Populate recipients table
      else end
    end

    recipientID = 1
    RAFFLEMANAGER_CONFIRM:RefreshData() -- Refresh scroll list
    RaffleManagerConfirmProgressBG:SetHidden(false)
    RaffleManagerConfirmTotalRecipients:SetColor(hex2rgb("#3A92FF"))
    RaffleManagerConfirmTotalRecipients:SetText("0/" .. #CurrentMail["recipients"])
    if (RAFFLEMANAGER_DEBUG) then d(guildChoice .. " (" .. #CurrentMail["recipients"] .. ")") end

    progressBarUnit = (500 / #CurrentMail["recipients"])
    if (RAFFLEMANAGER_DEBUG) then d("Progress Bar Unit = " .. progressBarUnit) end
  end

  OGS = OnGuildSelected

  for guildIndex = 1, GetNumGuilds() do
    guildId = GetGuildId(guildIndex)
    guildName = GetGuildName(guildId)
    GuildChoice[guildName] = guildId

    entry = manager.guildList:CreateItemEntry(guildName, OnGuildSelected) -- Populate guild dropdown box
    manager.guildList:AddItem(entry)

    table.insert(Guilds.GuildNames, guildName) -- Populate guild names table
  end

  return manager
end

-------------------------------------------------------------------------------
-- HANDLERS
-------------------------------------------------------------------------------

-- Mail

local function SaveMailAsPending()
  PendingMail["recipients"] = CurrentMail["recipients"]
  PendingMail["subject"] = CurrentMail["subject"]
  PendingMail["body"] = CurrentMail["body"]
end

local function SendNextRecipient()
  local recipient = nil
  local subject = PendingMail["subject"]
  local body = PendingMail["body"]

  RAFFLEMANAGER_ACTIVE = true
  recipient = PendingMail["recipients"][recipientID]
  tickets = TICKET_LOOKUP[recipient]
  barter = BARTER_LOOKUP[recipient]

  body = zo_strformat(body, recipient, tickets, barter)

  if not (mailBoxOpen) then RequestOpenMailbox() end

  --if (RAFFLEMANAGER_PAUSED) then
  --    RAFFLEMANAGER_ACTIVE = false
  --    CloseMailbox()
  --elseif (RAFFLEMANAGER_ACTIVE) then
  --    if lastKnownRecipient ~= recipient then
  --        SendMail(recipient, subject, body)
  --        lastKnownRecipient = recipient
  --    end
  --    zo_callLater(SendNextRecipient, throttleTimer)
  --end

  if (mailBoxOpen) then
    SendMail(recipient, subject, body)
    lastKnownRecipient = recipient
  elseif not (mailBoxOpen) then
    if not (RAFFLEMANAGER_PAUSED) then
      zo_callLater(SendNextRecipient, throttleTimer)
    else
      RAFFLEMANAGER_ACTIVE = false
      CloseMailbox()
    end
  end
end

local function RaffleManagerCancel()

  if (RAFFLEMANAGER_ACTIVE) then
    zo_callLater(RaffleManagerCancel, 200)
  else
    RAFFLEMANAGER_PAUSED = false

    for k, v in ipairs(Guilds.GuildMembers) do
      if v["mail"] == "|c3A92FFPending" then
        v["mail"] = "|cC80F14Canceled"
      else end
    end

    local progressBarCancelSize = (500 - progressBarTotal)
    RaffleManagerConfirmCancelProgressBar:SetDimensions(progressBarCancelSize, 24)
    RaffleManagerConfirmTotalRecipients:SetColor(hex2rgb("#AFAFAF"))
    RaffleManagerConfirmLastRecipient:SetText("")
    RAFFLEMANAGER_CONFIRM:RefreshData() -- Refresh scroll list
  end
end

local function UpdateProgressBar()
  progressBarTotal = progressBarTotal + progressBarUnit
  RaffleManagerConfirmProgressBar:SetDimensions(progressBarTotal, 24)
  RaffleManagerConfirmTotalRecipients:SetText(recipientID .. "/" .. #PendingMail["recipients"])
  RaffleManagerConfirmLastRecipient:SetText(lastKnownRecipient)
end

-- Events

local function OnMailSendSuccess()
  if (RAFFLEMANAGER_ACTIVE) then
    sentMailCount = sentMailCount + 1

    for k, v in ipairs(Guilds.GuildMembers) do
      if v["name"] == lastKnownRecipient then
        v["mail"] = "|c2DC50ESent"
      else end
    end

    RaffleManagerConfirmLastRecipient:SetColor(hex2rgb("#2DC50E"))
    UpdateProgressBar()
    RAFFLEMANAGER_CONFIRM:RefreshData() -- Refresh scroll list
    if (RAFFLEMANAGER_DEBUG) then d("|c2DC50E" .. lastKnownRecipient .. " " .. recipientID .. "/" .. #PendingMail["recipients"]) end

    if recipientID < #PendingMail["recipients"] then
      recipientID = recipientID + 1

      if not (RAFFLEMANAGER_PAUSED) then
        zo_callLater(SendNextRecipient, throttleTimer)
      else
        RAFFLEMANAGER_ACTIVE = false
        CloseMailbox()
      end

    else
      d("RaffleManager Completed")
      RAFFLEMANAGER_ACTIVE = false
      RAFFLEMANAGER_PAUSED = true
      CloseMailbox()
      RaffleManagerHideButtons()
      RaffleManagerConfirmTotalRecipients:SetColor(hex2rgb("#FFFFFF"))
      RaffleManagerConfirmLastRecipient:SetColor(hex2rgb("#EECA2A"))
      RaffleManagerConfirmLastRecipient:SetText("RaffleManager Completed")
    end

  else end
end

local function OnMailSendFailed(eventCode, reason)
  if (RAFFLEMANAGER_ACTIVE) then
    sentMailCount = sentMailCount + 1

    for k, v in ipairs(Guilds.GuildMembers) do
      if v["name"] == lastKnownRecipient then

        if reason == MAIL_SEND_RESULT_CANCELED then v["mail"] = "|cC80F14Canceled"
        elseif reason == MAIL_SEND_RESULT_CANT_SEND_TO_SELF then v["mail"] = "|cC80F14Can't send to self"
        elseif reason == MAIL_SEND_RESULT_FAIL_BLANK_MAIL then v["mail"] = "|cC80F14Blank Mail"
        elseif reason == MAIL_SEND_RESULT_FAIL_DB_ERROR then v["mail"] = "|cC80F14DB Error"
        elseif reason == MAIL_SEND_RESULT_FAIL_IGNORED then v["mail"] = "|cC80F14Ignored"
        elseif reason == MAIL_SEND_RESULT_FAIL_IN_PROGRESS then v["mail"] = "|cC80F14In progress"
        elseif reason == MAIL_SEND_RESULT_FAIL_INVALID_NAME then v["mail"] = "|cC80F14Invalid Name"
        elseif reason == MAIL_SEND_RESULT_FAIL_MAILBOX_FULL then v["mail"] = "|cC80F14Mailbox full"
        elseif reason == MAIL_SEND_RESULT_INVALID_ITEM then v["mail"] = "|cC80F14Invalid Item"
        elseif reason == MAIL_SEND_RESULT_MAIL_DISABLED then v["mail"] = "|cC80F14Mail Disabled"
        elseif reason == MAIL_SEND_RESULT_MAILBOX_NOT_OPEN then v["mail"] = "|cC80F14Mailbox Closed"
        elseif reason == MAIL_SEND_RESULT_CANT_SEND_CASH_COD then v["mail"] = "|cC80F14Can't send cash COD"
        elseif reason == MAIL_SEND_RESULT_NOT_ENOUGH_MONEY then v["mail"] = "|cC80F14Gold Error"
        elseif reason == NOT_ENOUGH_ITEMS_FOR_COD then v["mail"] = "|cC80F14Not enough items for COD"
        elseif reason == MAIL_SEND_RESULT_RECIPIENT_NOT_FOUND then v["mail"] = "|cC80F14Recipient Not Found"
        elseif reason == MAIL_SEND_RESULT_SUCCESS then v["mail"] = "|cC80F14Success"
        elseif reason == MAIL_SEND_RESULT_TOO_MANY_ATTACHMENTS then v["mail"] = "|cC80F14Too many attachments"
        else v["mail"] = "|cC80F14Unknown Error"
        end

      else end
    end

    RaffleManagerConfirmLastRecipient:SetColor(hex2rgb("#C80F14"))
    UpdateProgressBar()
    RAFFLEMANAGER_CONFIRM:RefreshData() -- Refresh scroll list
    if (RAFFLEMANAGER_DEBUG) then d("|cC80F14" .. lastKnownRecipient .. " " .. recipientID .. "/" .. #PendingMail["recipients"]) end

    if recipientID < #PendingMail["recipients"] then
      recipientID = recipientID + 1

      if not (RAFFLEMANAGER_PAUSED) then
        zo_callLater(SendNextRecipient, throttleTimer)
      else
        RAFFLEMANAGER_ACTIVE = false
        CloseMailbox()
      end

    else
      d("RaffleManager Completed")
      RAFFLEMANAGER_ACTIVE = false
      RAFFLEMANAGER_PAUSED = true
      CloseMailbox()
      RaffleManagerHideButtons()
      RaffleManagerConfirmTotalRecipients:SetColor(hex2rgb("#FFFFFF"))
      RaffleManagerConfirmLastRecipient:SetColor(hex2rgb("#EECA2A"))
      RaffleManagerConfirmLastRecipient:SetText("RaffleManager Completed")
    end

  else end
end

local function OnMailOpenMailBox()
  mailBoxOpen = true
end

local function OnMailCloseMailBox()
  mailBoxOpen = false
end

-- Tooltips

local function SetToolTip(ctrl, text, placement)
  ctrl:SetHandler("OnMouseEnter", function(self)
    ZO_Tooltips_ShowTextTooltip(self, placement, text)
  end)
  ctrl:SetHandler("OnMouseExit", function(self)
    ZO_Tooltips_HideTextTooltip()
  end)
end

-- Keybinds

function RaffleManagerWindow_Toggle()
  RAFFLEMANAGER_WINDOW:Toggle()
end

-------------------------------------------------------------------------------
-- GLOBAL XML
-------------------------------------------------------------------------------

-- Buttons

function RaffleManagerHideButtons()
  RaffleManagerMessageSendButton:SetHidden(false)
  RaffleManagerMessageCancelButton:SetHidden(true)
  RaffleManagerMessagePauseButton:SetHidden(true)
  RaffleManagerMessageContinueButton:SetHidden(true)
end

function RaffleManagerWindowCloseButton_OnClicked()
  RAFFLEMANAGER_WINDOW.visible = false
  RAFFLEMANAGER_WINDOW.control:SetHidden(true)
end

function RaffleManagerMessageSendButton_OnClicked()
  SaveMailAsPending()
  SendNextRecipient()

  RaffleManagerConfirmTotalRecipients:SetColor(hex2rgb("#2DC50E"))
  RaffleManagerMessageSendButton:SetHidden(true)
  RaffleManagerMessageCancelButton:SetHidden(false)
  RaffleManagerMessagePauseButton:SetHidden(false)
  if (RAFFLEMANAGER_DEBUG) then d("RaffleManager Started") end
end

function RaffleManagerMessageCancelButton_OnClicked()
  RAFFLEMANAGER_PAUSED = true
  RaffleManagerCancel()

  RaffleManagerMessageSendButton:SetHidden(false)
  RaffleManagerMessageCancelButton:SetHidden(true)
  RaffleManagerMessagePauseButton:SetHidden(true)
  RaffleManagerMessageContinueButton:SetHidden(true)
  if (RAFFLEMANAGER_DEBUG) then d("RaffleManager Canceled") end
end

function RaffleManagerMessagePauseButton_OnClicked()
  RAFFLEMANAGER_PAUSED = true

  RaffleManagerConfirmTotalRecipients:SetColor(hex2rgb("#3A92FF"))
  RaffleManagerMessagePauseButton:SetHidden(true)
  RaffleManagerMessageContinueButton:SetHidden(false)
  if (RAFFLEMANAGER_DEBUG) then d("RaffleManager Paused") end
end

function RaffleManagerMessageContinueButton_OnClicked()
  RAFFLEMANAGER_PAUSED = false
  SendNextRecipient()

  RaffleManagerConfirmTotalRecipients:SetColor(hex2rgb("#2DC50E"))
  RaffleManagerMessagePauseButton:SetHidden(false)
  RaffleManagerMessageContinueButton:SetHidden(true)
  if (RAFFLEMANAGER_DEBUG) then d("RaffleManager Continued") end
end

TICKET_LIST = {}

-- Import Field
function RaffleManagerImportField_OnTextChanged(self)
  local text = RaffleManagerExportImportField:GetText()

  local list = { zo_strsplit("|", text) }

  TICKET_LIST = {}

  for _, v in ipairs(list) do
    table.insert(TICKET_LIST, { zo_strsplit(",", v) })
  end
end

-- Cost field

function RaffleManagerMessageCostField_OnTextChanged(self)
  TICKET_COST = tonumber(RaffleManagerExportTicketCostField:GetText())

  if SavedVars then
    SavedVars.ticket_cost = TICKET_COST
  end
end

-- Subject Field

function RaffleManagerMessageSubjectField_OnInitialized(self)
  RaffleManagerMessageSubjectField:SetColor(hex2rgb("#AFAFAF"))
end

function RaffleManagerMessageSubjectField_OnTextChanged(self)
  CurrentMail["subject"] = RaffleManagerMessageSubjectField:GetText()
  if SavedVars then
    SavedVars.subject = CurrentMail["subject"]
  end
end

function RaffleManagerMessageSubjectField_OnFocusGained(self)
  if CurrentMail["subject"] == "(No subject)" then
    RaffleManagerMessageSubjectField:SetText("")
  end
  RaffleManagerMessageSubjectField:SetColor(hex2rgb("#FFFFFF"))
  PlaySound(SOUNDS.EDIT_CLICK)
end

function RaffleManagerMessageSubjectField_OnFocusLost(self)
  if CurrentMail["subject"] == "" then
    RaffleManagerMessageSubjectField:SetText("(No subject)")
    RaffleManagerMessageSubjectField:SetColor(hex2rgb("#AFAFAF"))
  end
end

-- Body Field

function RaffleManagerMessageBodyField_OnTextChanged(self)
  CurrentMail["body"] = RaffleManagerMessageBodyField:GetText()
  if SavedVars then
    SavedVars.body = CurrentMail["body"]
  end
  local CharCountBody = CharCounter(CurrentMail["body"])
  RaffleManagerMessageCharacterLimit:SetText(CharCountBody .. "/700")
end

-- Scroll List

function RaffleManagerConfirmRow_OnMouseEnter(control)
  RAFFLEMANAGER_CONFIRM:EnterRow(control)
end

function RaffleManagerConfirmRow_OnMouseExit(control)
  RAFFLEMANAGER_CONFIRM:ExitRow(control)
end

-- Labels

function RaffleManagerLabelField_OnMouseEnter(control)
  if (control:WasTruncated()) then
    InitializeTooltip(InformationTooltip, control, BOTTOM, 0, 0)
    SetTooltipText(InformationTooltip, control:GetText())
  end

  local row = control:GetParent()
  zo_callHandler(row, "OnMouseEnter")
end

function RaffleManagerLabelField_OnMouseExit(control)
  ClearTooltip(InformationTooltip)

  local row = control:GetParent()
  zo_callHandler(row, "OnMouseExit")
end

function RaffleManagerLabelField_OnLinkMouseUp(control, button, linkText)
  ZO_LinkHandler_OnLinkMouseUp(linkText, button, control)

  local row = control:GetParent()
  zo_callHandler(row, "OnMouseUp", button, true, linkText)
end

-- Initialize

function RaffleManagerWindow_OnInitialized(self)
  RAFFLEMANAGER_WINDOW = RaffleManagerWindow:New(self)
end

function RaffleManagerExport_OnInitialized(self)
  RAFFLEMANAGER_COMPOSE = RaffleManagerExport:New(self)
end

function RaffleManagerConfirm_OnInitialized(self)
  RAFFLEMANAGER_CONFIRM = RaffleManagerConfirm:New(self)
end

function RaffleManagerMessage_OnInitialized(self)
  RAFFLEMANAGER_MESSAGE = RaffleManagerMessage:New(self)
end

-------------------------------------------------------------------------------
-- ADDON LOADED
-------------------------------------------------------------------------------

local function OnAddonLoaded(eventCode, addonName)
  local mm_detected = false
  if MasterMerchant then
    if MasterMerchant.isInitialized then mm_detected = true end
  end
  if addonName ~= (ADDON_NAME) and not mm_detected then return end

  SavedVars = ZO_SavedVars:NewAccountWide(SAVEDVARS_NAME, SAVEDVARS_VERSION, nil, DefaultVars)

  SLASH_COMMANDS["/ram"] = RaffleManagerWindow_Toggle

  if SavedVars then
    if SavedVars.body then
      CurrentMail["body"] = SavedVars.body
      RaffleManagerMessageBodyField:SetText(SavedVars.body)
    end
    if SavedVars.subject then
      CurrentMail["subject"] = SavedVars.subject
      RaffleManagerMessageSubjectField:SetText(SavedVars.subject)
    end
    if SavedVars.cost then
      TICKET_COST = tonumber(SavedVars.cost)
    else
      TICKET_COST = 1000
    end
    RaffleManagerExportTicketCostField:SetText(TICKET_COST)
  end

  EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_MAIL_OPEN_MAILBOX, OnMailOpenMailBox)
  EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_MAIL_CLOSE_MAILBOX, OnMailCloseMailBox)
  EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_MAIL_SEND_SUCCESS, OnMailSendSuccess)
  EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_MAIL_SEND_FAILED, OnMailSendFailed)

  EVENT_MANAGER:UnregisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED)
end

EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, OnAddonLoaded)
