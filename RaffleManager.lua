local internal = _G["LibGuildStore_Internal"]
local LAM = LibAddonMenu2

local ADDON_NAME = "RaffleManager"
local ADDON_VERSION = "5.0.5"
local SAVEDVARS_NAME = "RaffleManager_SavedVariables"
local SAVEDVARS_VERSION = 1

local RAFFLEMANAGER_DEBUG = true
local RAFFLEMANAGER_ACTIVE = false
local RAFFLEMANAGER_PAUSED = false

local RAFFLEMANAGER_WINDOW = nil
local RAFFLEMANAGER_COMPOSE = nil
local RAFFLEMANAGER_CONFIRM = nil
local RAFFLEMANAGER_MESSAGE = nil
local RAFFLEMANAGER_INBOX = nil
local RAFFLEMANAGER_SENT = nil
local RAFFLEMANAGER_MAIL_MAX_BODY_CHARACTERS = 550

local TOTAL_CONTRIBUTION_LOOKUP = {}
local RANK_LOOKUP = {}
local PERCENT_LOOKUP = {}
local PURCHASE_TAX_LOOKUP = {}
local RAFFLE_TICKETS_LOOKUP = {}
local AUCTIONS_LOOKUP = {}

local AMT_DATERANGE_TODAY = 1
local AMT_DATERANGE_YESTERDAY = 2
local AMT_DATERANGE_THISWEEK = 3
local AMT_DATERANGE_LASTWEEK = 4
local AMT_DATERANGE_PRIORWEEK = 5
local AMT_DATERANGE_7DAY = 6
local AMT_DATERANGE_10DAY = 7
local AMT_DATERANGE_30DAY = 8

local CONFIRM_SORT_KEYS = {
  ["name"] = { },
  ["mail"] = { tiebreaker = "name" },
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
local TICKET_LIST = {}
local ROSTER_EXPORT = {}

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

local DefaultVars = {
  ticket_cost = 1000,
  body = "",
  subject = "",
  data_range = 10,
}
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
  local export_data = {}

  for i = 1, GetNumGuildMembers(gnum) do
    local account, note, rankindex = GetGuildMemberInfo(gnum, i)

    local rank_name = GetGuildRankCustomName(gnum, rankindex)

    local line = {
      account = account,
      sales10 = 0,
      sales30 = 0,
      salesTax10 = 0,
      salesTax30 = 0,
      purchases10 = 0,
      purchases30 = 0,
      purchaseTax10 = 0,
      purchaseTax30 = 0,
      joined = 0,
      bankgoldAddedThisWeek = 0,
      bankgoldAddedLastWeek = 0,
      rank = rank_name,
    }


    local masterMerchantSalesAccount, masterMerchantPurchasesAccount
    local masterMerchantSales = internal.guildSales[gname].sellers
    local masterMerchantPurchases = internal.guildPurchases[gname].sellers
    if not masterMerchantSales[account] and not masterMerchantPurchases[account] then
      CHAT_SYSTEM:AddMessage("Skipping " .. account .. " as no MasterMerchant data.")
    else
      masterMerchantSalesAccount = masterMerchantSales[account]
      masterMerchantPurchasesAccount = masterMerchantPurchases[account]
      if not masterMerchantSalesAccount or not masterMerchantSalesAccount.sales then
        CHAT_SYSTEM:AddMessage("No sales for " .. account)
      else
        line.sales10 = masterMerchantSalesAccount.sales[MM_DATERANGE_10DAY]
        line.sales30 = masterMerchantSalesAccount.sales[MM_DATERANGE_30DAY]
        if line.sales10 == nil then line.sales10 = 0 end
        if line.sales30 == nil then line.sales30 = 0 end
        line.salesTax10 = masterMerchantSalesAccount.tax[MM_DATERANGE_10DAY]
        line.salesTax30 = masterMerchantSalesAccount.tax[MM_DATERANGE_30DAY]
        if line.salesTax10 == nil then line.salesTax10 = 0 end
        if line.salesTax30 == nil then line.salesTax30 = 0 end
      end

      if not masterMerchantPurchasesAccount or not masterMerchantPurchasesAccount.sales then
        CHAT_SYSTEM:AddMessage("No purchases for " .. account)
      else
        line.purchases10 = masterMerchantPurchasesAccount.sales[MM_DATERANGE_10DAY]
        line.purchases30 = masterMerchantPurchasesAccount.sales[MM_DATERANGE_30DAY]
        if line.purchases10 == nil then line.purchases10 = 0 end
        if line.purchases30 == nil then line.purchases30 = 0 end
        line.purchaseTax10 = masterMerchantPurchasesAccount.tax[MM_DATERANGE_10DAY]
        line.purchaseTax30 = masterMerchantPurchasesAccount.tax[MM_DATERANGE_30DAY]
        if line.purchaseTax10 == nil then line.purchaseTax10 = 0 end
        if line.purchaseTax30 == nil then line.purchaseTax30 = 0 end
      end
    end

    if AMT ~= nil and AMT.savedData ~= nil and AMT.savedData[gname] ~= nil then
      local username = account:lower()
      if AMT.savedData[gname][username] ~= nil then
        local joinDate = AMT.savedData[gname][username].timeJoined
        local bankgoldAddedThisWeek = AMT.savedData[gname][username][GUILD_EVENT_BANKGOLD_ADDED][AMT_DATERANGE_THISWEEK].total
        local bankgoldAddedLastWeek = AMT.savedData[gname][username][GUILD_EVENT_BANKGOLD_ADDED][AMT_DATERANGE_LASTWEEK].total
        line.joined = joinDate
        line.bankgoldAddedThisWeek = bankgoldAddedThisWeek
        line.bankgoldAddedLastWeek = bankgoldAddedLastWeek
      end
    end

    local exportSalesTax
    local exportPurchaseTax
    if SavedVars.data_range == 10 then exportSalesTax = line.salesTax10
    elseif SavedVars.data_range == 30 then exportSalesTax = line.salesTax30 end
    if SavedVars.data_range == 10 then exportPurchaseTax = line.purchaseTax10
    elseif SavedVars.data_range == 30 then exportPurchaseTax = line.purchaseTax30 end

    local exportLine = string.format("%s&%s&%s&%s&%s", line.account, exportSalesTax, exportPurchaseTax, line.bankgoldAddedThisWeek, line.joined)
    table.insert(export_data, exportLine)
    table.insert(data, line)
  end

  SavedVars.roster_timestamp = GetTimeStamp()
  SavedVars.roster_data = data
  SavedVars.roster_export_data = export_data
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
  local export = {}

  for i in ZO_GetNextMailIdIter do
    local senderDisplayName, senderCharacterName, subject, icon, unread, fromSystem, fromCS, returned, numAttachments, attachedMoney, codAmount, expiresInDays, secsSinceReceived = GetMailItemInfo(i)
    if attachedMoney ~= 0 and not returned and not fromCS and not fromSystem and subject ~= "Item Sold" and (attachedMoney % SavedVars.ticket_cost == 0) then
      table.insert(events, { user = senderDisplayName, subject = subject, amount = attachedMoney, id = Id64ToString(i) })
      local ticketCount = attachedMoney / SavedVars.ticket_cost
      local exportString = string.format("%s&%s", senderDisplayName, ticketCount)
      table.insert(export, exportString)
    end
  end

  SavedVars.mail_data = events
  SavedVars.mail_export_data = export
  SavedVars.timestamp = GetTimeStamp()

  CHAT_SYSTEM:AddMessage(#events .. " mail events stored. Reload your UI to updated SavedVariables.")
end

function RaffleManager_ParseBank()
  if SELECTED_GUILD == nil then
    CHAT_SYSTEM:AddMessage("Select a guild before exporting!")
    return
  end

  if LOADING_EVENTS then
    CHAT_SYSTEM:AddMessage("Still loading events!")
    return
  end

  local gnum = GuildChoice[SELECTED_GUILD]
  return _RaffleManager_ParseBank(gnum)
end

function _RaffleManager_ParseBank(gnum)
  local num_events = GetNumGuildEvents(gnum, GUILD_HISTORY_BANK)

  --[[Replace with LibHistorie
  while RequestGuildHistoryCategoryNewest(gnum, GUILD_HISTORY_BANK) do
  end
  ]]--

  CHAT_SYSTEM:AddMessage("(Not Active or Updated) ; Parsing " .. num_events .. " bank events for tickets.")

  local events = {}

  --[[Replace with LibHistorie
  for i = 1, num_events do
      local etype, secs, par1, par2, par3, par4, par5, par6 = GetGuildEventInfo(gnum, GUILD_HISTORY_BANK, i)
      if etype == GUILD_EVENT_BANKGOLD_ADDED and secs < ten_days and (par2 % SavedVars.ticket_cost == 0) then
          local user = par1
          local amount = par2
          local _ts = GetTimeStamp() - secs
          local uniq_id = Id64ToString(GetGuildEventId(gnum, GUILD_HISTORY_BANK, i))
          table.insert(events, { user = user, amount = amount, timestamp = _ts, id = uniq_id})
      end
  end

  table.sort(events, function (k1, k2) return k1.timestamp > k2.timestamp end)
  ]]--

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
  manager.sortHeaderGroup:SelectHeaderByKey("name")

  return manager
end

function RaffleManagerConfirm:SetupRow(control, data)
  ZO_SortFilterList.SetupRow(self, control, data)

  control:SetHandler("OnMouseUp", function(control, button, upInside, linkText) self:OnRowMouseUp(control, button, upInside, linkText) end)

  local playerLink = ("|H0:display:%s|h%s|h"):format(data.name, data.name)
  GetControl(control, "ID"):SetText(data.id)
  GetControl(control, "Name"):SetText(playerLink)
  GetControl(control, "Rank"):SetText(data.rank)
  GetControl(control, "TotalContribution"):SetText(data.totalContribution)
  GetControl(control, "Percent"):SetText(data.percent)
  GetControl(control, "PurchaseTax"):SetText(data.purchaseTax)
  GetControl(control, "RaffleTickets"):SetText(data.raffleTickets)
  GetControl(control, "Auctions"):SetText(data.auctions)
  GetControl(control, "Mail"):SetText(data.mail)
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

  manager.confirmations = control:GetNamedChild("ImportField")
  manager.confirmations:SetMaxInputChars(2000)

  local function OnGuildSelected (_, name, choice)
    SELECTED_GUILD = name
  end

  for guildIndex = 1, GetNumGuilds() do
    local guildId = GetGuildId(guildIndex)
    local guildName = GetGuildName(guildId)
    GuildChoice[guildName] = guildId

    local guildIndexEntry = manager.guildList:CreateItemEntry(guildName, OnGuildSelected) -- Populate guild dropdown box
    manager.guildList:AddItem(guildIndexEntry)
  end
end

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
  manager.body:SetMaxInputChars(RAFFLEMANAGER_MAIL_MAX_BODY_CHARACTERS)

  local guildChoiceID

  local function OnGuildSelected (_, guildChoice, choice)
    RaffleManagerConfirmLastRecipient:SetText("")
    RaffleManagerConfirmProgressBar:SetDimensions(0, 24)
    RaffleManagerConfirmCancelProgressBar:SetDimensions(0, 24)

    Guilds.GuildMembers = {}
    CurrentMail["recipients"] = {}
    RANK_LOOKUP = {}
    TOTAL_CONTRIBUTION_LOOKUP = {}
    PERCENT_LOOKUP = {}
    PURCHASE_TAX_LOOKUP = {}
    RAFFLE_TICKETS_LOOKUP = {}
    AUCTIONS_LOOKUP = {}

    progressBarTotal = 0
    progressBarUnit = 0
    sentMailCount = 0
    recipientID = 1

    guildChoiceID = GuildChoice[guildChoice] -- Set selected guild ID

    for numGuildMembers = 1, GetNumGuildMembers(guildChoiceID) do
      local name, note, rankIndex, playerStatus, secsSinceLogoff = GetGuildMemberInfo(guildChoiceID, numGuildMembers)

      if #TICKET_LIST >= 1 then
        for ti = 1, #TICKET_LIST do
          local n, rank, totalContribution, percent, purchaseTax, raffleTickets, auctions = unpack(TICKET_LIST[ti])
          if rank == nil then rank = 0 end
          if type(rank) ~= 'number' then rank = tonumber(rank) end
          if totalContribution == nil then totalContribution = 0 end
          if percent == nil then percent = 0 end
          if purchaseTax == nil then purchaseTax = 0 end
          if raffleTickets == nil then raffleTickets = 0 end
          if auctions == nil then auctions = 0 end
          n = n:gsub("%p", "%%%1")
          if name:match("^@" .. n .. "$") ~= nil then
            RANK_LOOKUP[name] = rank
            TOTAL_CONTRIBUTION_LOOKUP[name] = totalContribution
            PERCENT_LOOKUP[name] = percent
            PURCHASE_TAX_LOOKUP[name] = purchaseTax
            RAFFLE_TICKETS_LOOKUP[name] = raffleTickets
            AUCTIONS_LOOKUP[name] = auctions
            table.insert(Guilds.GuildMembers, { id = 0, name = name, mail = true, rank = rank, totalContribution = totalContribution, percent = percent, purchaseTax = purchaseTax, raffleTickets = raffleTickets, auctions = auctions }) -- Populate guild members table
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

    progressBarUnit = (905 / #CurrentMail["recipients"])
    if (RAFFLEMANAGER_DEBUG) then d("Progress Bar Unit = " .. progressBarUnit) end
  end

  OGS = OnGuildSelected

  for guildIndex = 1, GetNumGuilds() do
    local guildId = GetGuildId(guildIndex)
    local guildName = GetGuildName(guildId)
    GuildChoice[guildName] = guildId

    local guildIndexEntry = manager.guildList:CreateItemEntry(guildName, OnGuildSelected) -- Populate guild dropdown box
    manager.guildList:AddItem(guildIndexEntry)

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

  local function GetRaffleTicketsCount(raffleTickets)
    local returnValue = 0
    if tonumber(raffleTickets) > 0 then returnValue = tonumber(raffleTickets) / tonumber(SavedVars.ticket_cost) end
    if returnValue <= 0 then returnValue = 0 end
    return returnValue
  end

  local function GetRosterDataByName(recipient)
    -- SavedVars.roster_data
    local returnValue = nil
    for k, memberData in ipairs(SavedVars.roster_data) do
      if recipient == memberData.account then return memberData end
    end
    return returnValue
  end

  local function GetTotalSales(recipient)
    local memberData = GetRosterDataByName(recipient)
    if SavedVars.data_range == 10 then return tonumber(memberData.sales10)
    elseif SavedVars.data_range == 30 then return tonumber(memberData.sales30) end
  end

  local function GetTotalPurchases(recipient)
    local memberData = GetRosterDataByName(recipient)
    if SavedVars.data_range == 10 then return tonumber(memberData.purchases10)
    elseif SavedVars.data_range == 30 then return tonumber(memberData.purchases30) end
  end

  local function GetSalesTax(recipient)
    local memberData = GetRosterDataByName(recipient)
    if SavedVars.data_range == 10 then return tonumber(memberData.salesTax10)
    elseif SavedVars.data_range == 30 then return tonumber(memberData.salesTax30) end
  end

  local function GetPurchaseTax(recipient)
    local memberData = GetRosterDataByName(recipient)
    if SavedVars.data_range == 10 then return tonumber(memberData.purchaseTax10)
    elseif SavedVars.data_range == 30 then return tonumber(memberData.purchaseTax30) end
  end

  local function GetBankgoldAdded(recipient)
    local memberData = GetRosterDataByName(recipient)
    return memberData.bankgoldAddedThisWeek
  end

  local subject = PendingMail["subject"]
  local mailBody = PendingMail["body"]
  local body = ""

  RAFFLEMANAGER_ACTIVE = true
  local recipient = PendingMail["recipients"][recipientID]
  local memberData = GetRosterDataByName(recipient)
  local rank = RANK_LOOKUP[recipient]
  local totalContribution = tonumber(TOTAL_CONTRIBUTION_LOOKUP[recipient])
  local percent = PERCENT_LOOKUP[recipient]
  local sales = GetTotalSales(recipient)
  local purchases = GetTotalPurchases(recipient)
  local salesTax = GetSalesTax(recipient)
  local purchaseTax = GetPurchaseTax(recipient)
  local raffleTickets = GetRaffleTicketsCount(RAFFLE_TICKETS_LOOKUP[recipient])
  local auctions = tonumber(AUCTIONS_LOOKUP[recipient])
  local goldAdded = GetBankgoldAdded(recipient)

  body = string.format("Hello %s,\n\nSales: %s\nSales tax: %s\nPurchases: %s\nPurchase tax: %s\nGold Deposits: %s\n\n", recipient, ZO_LocalizeDecimalNumber(sales), ZO_LocalizeDecimalNumber(salesTax), ZO_LocalizeDecimalNumber(purchases), ZO_LocalizeDecimalNumber(purchaseTax), ZO_LocalizeDecimalNumber(goldAdded))
  body = body .. zo_strformat(mailBody, rank, ZO_LocalizeDecimalNumber(totalContribution), percent, ZO_LocalizeDecimalNumber(purchaseTax), raffleTickets, ZO_LocalizeDecimalNumber(auctions))

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

-- Import Field
function RaffleManagerImportField_OnTextChanged(self)
  local text = RaffleManagerExportImportField:GetText()

  local list = { zo_strsplit("&", text) }

  TICKET_LIST = {}

  for _, v in ipairs(list) do
    table.insert(TICKET_LIST, { zo_strsplit(",", v) })
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
  RaffleManagerMessageCharacterLimit:SetText(CharCountBody .. "/550")
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
-- LAM
-------------------------------------------------------------------------------

local function LibAddonInit()
  local panelData = {
    type = 'panel',
    name = ADDON_NAME,
    displayName = 'Raffle Manager',
    author = "nooblybear, |cFF9B15Sharlikran|r",
    version = ADDON_VERSION,
    -- registerForRefresh = true,
    -- registerForDefaults = true,
  }

  local optionsData = {}
  optionsData[#optionsData + 1] = {
    type = "header",
    name = ADDON_NAME,
    width = "full",
  }
  optionsData[#optionsData + 1] = {
    type = "editbox",
    name = "Raffle Ticket Cost",
    isMultiline = false,
    textType = TEXT_TYPE_NUMERIC,
    getFunc = function() return SavedVars.ticket_cost end,
    setFunc = function(value) SavedVars.ticket_cost = value end,
    default = DefaultVars.ticket_cost,
  }
  optionsData[#optionsData + 1] = {
    type = 'dropdown',
    name = "Data Range",
    choices = { "10 Days", "30 Days", },
    choicesValues = { 10, 30, },
    getFunc = function() return SavedVars.data_range end,
    setFunc = function(value) SavedVars.data_range = value end,
    default = DefaultVars.data_range,
  }

  LAM:RegisterAddonPanel('RaffleManagerOptions', panelData)
  LAM:RegisterOptionControls('RaffleManagerOptions', optionsData)
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

  LibAddonInit()

  SLASH_COMMANDS["/ram"] = RaffleManagerWindow_Toggle

  CurrentMail["body"] = SavedVars.body
  RaffleManagerMessageBodyField:SetText(SavedVars.body)
  CurrentMail["subject"] = SavedVars.subject
  RaffleManagerMessageSubjectField:SetText(SavedVars.subject)

  EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_MAIL_OPEN_MAILBOX, OnMailOpenMailBox)
  EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_MAIL_CLOSE_MAILBOX, OnMailCloseMailBox)
  EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_MAIL_SEND_SUCCESS, OnMailSendSuccess)
  EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_MAIL_SEND_FAILED, OnMailSendFailed)

  EVENT_MANAGER:UnregisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED)
end

EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, OnAddonLoaded)
