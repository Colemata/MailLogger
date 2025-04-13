-- MailLogger: Track items received from mail
-- Author: Claude
-- Version: 2.5

-- Initialize addon
local addonName, MailLogger = ...
MailLogger = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0", "AceHook-3.0")

-- Variables
MailLogger.itemLog = {}
MailLogger.db = nil
MailLogger.mailProcessing = false
MailLogger.currentCharacter = nil
MailLogger.pendingItemLookups = {}
MailLogger.itemCache = {}
MailLogger.exportFrame = nil

-- Default settings
local defaults = {
    global = {
        characters = {},
        itemCache = {},
    },
    char = {
        itemLog = {},
    },
    profile = {
        autoShowExport = true,
        summedExport = false,
        inventoryFormat = true,
    }
}

-- Debug helper function to print the stack trace
function MailLogger:PrintDebugStack(msg)
    if self.debug then
        self:Print("DEBUG: " .. (msg or "Stack trace:"))
        self:Print(debugstack(2, 20, 20))
    end
end

function MailLogger:OnInitialize()
    -- Set up saved variables database with per-character data
    self.db = LibStub("AceDB-3.0"):New("MailLoggerDB", defaults, true)
    
    -- Store current character name and settings
    self.currentCharacter = UnitName("player") .. "-" .. GetRealmName()
    self.itemLog = self.db.char.itemLog
    self.itemCache = self.db.global.itemCache
    self.autoShowExport = self.db.profile.autoShowExport
    self.summedExport = self.db.profile.summedExport
    self.inventoryFormat = self.db.profile.inventoryFormat
    
    -- Register character in global list
    self.db.global.characters[self.currentCharacter] = true
    
    -- Register slash commands and events
    self:RegisterChatCommand("maillog", "SlashCommand")
    self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    
    -- Print loaded message
    self:Print("MailLogger v2.5 loaded for " .. self.currentCharacter .. ". Type /maillog for commands.")
end

function MailLogger:OnEnable()
    -- Register events
    self:RegisterEvent("MAIL_SHOW")
    self:RegisterEvent("MAIL_CLOSED")
    self:RegisterEvent("MAIL_INBOX_UPDATE")
    
    -- Hook mail functions
    self:SecureHook("TakeInboxItem", "OnTakeInboxItem")
    self:SecureHook("TakeInboxMoney", "OnTakeInboxMoney")
    self:SecureHook("AutoLootMailItem", "OnAutoLootMailItem")
end

-- Safely attempt to focus the mail frame
function MailLogger:SafeFocusMailFrame()
    -- Only attempt to set focus if MailFrame exists and is shown
    if MailFrame and MailFrame:IsShown() and MailFrame.SetFocus then
        MailFrame:SetFocus()
    end
end

-- Handle item info received from server
function MailLogger:GET_ITEM_INFO_RECEIVED(event, itemID, success)
    if not itemID or not success then return end
    
    -- Get item name from cache
    local name = GetItemInfo(itemID)
    if name and self.pendingItemLookups[itemID] then
        -- Cache the item name by ID
        self.itemCache[tostring(itemID)] = name
        self.db.global.itemCache = self.itemCache
        
        -- Update any pending log entries for this item
        for _, entryInfo in ipairs(self.pendingItemLookups[itemID]) do
            local index = entryInfo.index
            if self.itemLog[index] then
                self.itemLog[index].itemName = name
                if self.debug then
                    self:Print("Updated item name for entry #" .. index .. " to: " .. name)
                end
            end
        end
        
        -- Clear pending lookups for this item
        self.pendingItemLookups[itemID] = nil
        
        -- Save the updated log and refresh display
        self.db.char.itemLog = self.itemLog
        self:RefreshExportFrame()
    end
end

function MailLogger:MAIL_SHOW()
    if self.debug then self:Print("Mail window opened.") end
    
    -- Automatically show export pane if enabled
    if self.autoShowExport then
        C_Timer.After(0.2, function() 
            self:ShowExportPane() 
        end)
    end
end

function MailLogger:MAIL_CLOSED()
    if self.debug then self:Print("Mail window closed.") end
    -- Deliberately not closing export frame here
end

function MailLogger:MAIL_INBOX_UPDATE()
    if self.debug then self:Print("Mail inbox updated.") end
    
    -- Process any pending mail tracking
    if self.mailProcessing then
        self:ProcessPendingMail()
    end
    
    -- Refresh the export frame if it's open
    self:RefreshExportFrame()
end

-- Helper function to process mail items when taken
function MailLogger:ProcessMailItem(sender, itemName, count, itemLink, itemID)
    if sender and count and count > 0 then
        self:LogMailItem(sender, itemName, count, time(), itemLink, itemID)
        if self.debug then
            self:Print("Logged item: " .. (itemName or "Unknown Item") .. " (ID: " .. (itemID or "none") .. ")")
        end
        
        -- Refresh the export frame after a short delay to ensure all data is processed
        C_Timer.After(0.2, function() self:RefreshExportFrame() end)
        return true
    end
    return false
end

function MailLogger:OnTakeInboxItem(mailIndex, attachmentIndex)
    if self.debug then
        self:Print("Taking inbox item: " .. mailIndex .. ", attachment: " .. (attachmentIndex or "nil"))
    end
    
    -- Store the mail info for tracking
    local sender, _, _, _, _, itemName, _, count, itemLink, itemID = self:GetMailInfo(mailIndex, attachmentIndex)
    
    if not self:ProcessMailItem(sender, itemName, count, itemLink, itemID) then
        -- Set up for delayed processing
        self.mailProcessing = true
        self.pendingMailIndex = mailIndex
        self.pendingAttachmentIndex = attachmentIndex
    end
end

function MailLogger:OnAutoLootMailItem(mailIndex)
    if self.debug then
        self:Print("Auto-looting mail item: " .. mailIndex)
    end
    
    -- Get mail sender
    local sender = select(3, GetInboxHeaderInfo(mailIndex)) or "Unknown"
    
    -- Process each attachment
    for i = 1, ATTACHMENTS_MAX_RECEIVE do
        local name, itemID, _, count = GetInboxItem(mailIndex, i)
        local _, _, _, _, _, _, _, _, _, itemLink = GetInboxItemLink(mailIndex, i)
        
        self:ProcessMailItem(sender, name, count, itemLink, itemID)
    end
end

-- Modified function to handle money more consistently
function MailLogger:OnTakeInboxMoney(mailIndex)
    if self.debug then
        self:Print("Taking inbox money: " .. mailIndex)
    end
    
    -- Get mail info
    local _, _, sender, _, money = GetInboxHeaderInfo(mailIndex)
    
    if sender and money and money > 0 then
        -- Format money in gold, silver, copper
        local gold = floor(money / 10000)
        local silver = floor((money % 10000) / 100)
        local copper = money % 100
        
        -- Create consistent format without spaces between numbers and g/s/c
        local moneyText = gold .. "g " .. silver .. "s " .. copper .. "c"
        
        -- Store raw copper value for more accurate summing
        local entry = {
            sender = sender or "Unknown",
            itemName = "Gold",
            count = moneyText,
            timestamp = time(),
            date = date("%Y-%m-%d %H:%M:%S"),
            rawCopper = money -- Store the raw copper value
        }
        
        -- Add to the character-specific log
        local entryIndex = #self.itemLog + 1
        self.itemLog[entryIndex] = entry
        
        -- Save the updated log
        self.db.char.itemLog = self.itemLog
        
        -- Notify the user
        self:Print(string.format("Logged: %s sent you %s", sender, moneyText))
        
        -- Refresh the export frame if it's open
        self:RefreshExportFrame()
        
        if self.debug then
            self:Print("Logged money: " .. moneyText .. " (" .. money .. " copper)")
        end
    end
    
    -- Refresh the export frame
    C_Timer.After(0.2, function() self:RefreshExportFrame() end)
end

function MailLogger:ProcessPendingMail()
    -- Clear processing flag
    self.mailProcessing = false
    
    if not self.pendingMailIndex then return end
    
    -- Try to get mail info again
    local sender, _, _, _, _, itemName, _, count, itemLink, itemID = self:GetMailInfo(self.pendingMailIndex, self.pendingAttachmentIndex)
    
    self:ProcessMailItem(sender, itemName, count, itemLink, itemID)
    
    -- Clear pending variables
    self.pendingMailIndex = nil
    self.pendingAttachmentIndex = nil
end

function MailLogger:GetMailInfo(mailIndex, attachmentIndex)
    if not mailIndex then return nil end
    
    -- Get mail header info
    local _, _, sender, subject, money, _, _, hasItem = GetInboxHeaderInfo(mailIndex)
    
    -- Get item info if attachment index provided
    local itemName, itemID, itemTexture, count, quality, canUse = nil, nil, nil, nil, nil, nil
    local itemLink = nil
    
    if attachmentIndex then
        itemName, itemID, itemTexture, count, quality, canUse = GetInboxItem(mailIndex, attachmentIndex)
        
        -- Try to get item link if we have an item
        if count and count > 0 then
            _, _, _, _, _, _, _, _, _, itemLink = GetInboxItemLink(mailIndex, attachmentIndex)
        end
    end
    
    return sender, subject, money, hasItem and 1 or 0, false, itemName, itemTexture, count, itemLink, itemID
end

-- Extract item ID from an item link
function MailLogger:GetItemIDFromLink(itemLink)
    if not itemLink then return nil end
    
    local itemID = itemLink:match("item:(%d+)")
    return itemID and tonumber(itemID) or nil
end

-- Clean export format text only for export
function MailLogger:CleanTextForExport(text)
    if not text then return "Unknown Item" end
    
    -- Remove color codes and link formatting
    local cleaned = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")
    
    -- If cleaned text is empty, return Unknown Item
    if cleaned:trim() == "" then
        return "Unknown Item"
    end
    
    return cleaned
end

-- Get a safe item name that won't be blank
function MailLogger:GetSafeItemName(itemName, itemLink, itemID)
    -- If we have an item name and it's not empty after cleaning, use it
    if itemName and self:CleanTextForExport(itemName):trim() ~= "" then
        return itemName
    end
    
    -- If we have an item ID, try to get the name from cache or game
    if itemID then
        local cachedName = self.itemCache[tostring(itemID)]
        if cachedName then return cachedName end
        
        local name = GetItemInfo(itemID)
        if name then
            self.itemCache[tostring(itemID)] = name
            self.db.global.itemCache = self.itemCache
            return name
        end
    end
    
    -- If we have an item link but no name, try to extract the ID
    if itemLink and not itemID then
        itemID = self:GetItemIDFromLink(itemLink)
        if itemID then
            local cachedName = self.itemCache[tostring(itemID)]
            if cachedName then return cachedName end
            
            local name = GetItemInfo(itemID)
            if name then
                self.itemCache[tostring(itemID)] = name
                self.db.global.itemCache = self.itemCache
                return name
            end
        end
    end
    
    -- If all else fails, return Unknown Item
    return "Unknown Item"
end

function MailLogger:LogMailItem(sender, itemName, count, timestamp, itemLink, itemID)
    -- Make sure we have a valid sender
    if sender == nil then sender = "Unknown" end
    
    -- Handle item name with special care
    local safeItemName = self:GetSafeItemName(itemName, itemLink, itemID)
    
    -- Create a new log entry
    local entry = {
        sender = sender,
        itemName = safeItemName,
        count = count,
        timestamp = timestamp or time(),
        date = date("%Y-%m-%d %H:%M:%S", timestamp or time()),
        itemID = itemID, -- Store item ID for potential future lookup
    }
    
    -- Add to the character-specific log
    local entryIndex = #self.itemLog + 1
    self.itemLog[entryIndex] = entry
    
    -- If the item name is still problematic and we have an ID, set up a pending lookup
    if safeItemName == "Unknown Item" and itemID then
        if not self.pendingItemLookups[itemID] then
            self.pendingItemLookups[itemID] = {}
        end
        table.insert(self.pendingItemLookups[itemID], {index = entryIndex})
    end
    
    -- Save the updated log
    self.db.char.itemLog = self.itemLog
    
    -- Notify the user
    self:Print(string.format("Logged: %s sent you %s %s", sender, count, safeItemName))
    
    -- Refresh the export frame if it's open
    self:RefreshExportFrame()
end

function MailLogger:SlashCommand(input)
    local command, argument = strsplit(" ", input:trim(), 2)
    
    local commandHandlers = {
        help = function() self:PrintHelp() end,
        show = function() self:ShowLog() end,
        export = function() self:ExportLog() end,
        clear = function() self:ClearLog() end,
        debug = function() self:ToggleDebug() end,
        list = function() self:ListCharacters() end,
        sum = function() self:ExportSummedLog() end,
        fix = function() self:FixBlankItems() end,
        toggle = function() self:ToggleExportPane() end,
        auto = function() self:ToggleAutoShow() end,
        summode = function() self:ToggleSummedMode() end,
        format = function() self:ToggleInventoryFormat() end, 
        test = function() self:TestExportPane() end -- Added for testing
    }
    
    if commandHandlers[command] then
        commandHandlers[command]()
    else
        self:PrintHelp()
    end
end

-- Test function to debug export pane display
function MailLogger:TestExportPane()
    self:Print("Testing export pane display...")
    
    if self.exportFrame then
        self:Print("Export frame exists")
        if self.exportFrame:IsShown() then
            self:Print("Export frame is shown")
        else
            self:Print("Export frame is hidden, attempting to show")
            self.exportFrame:Show()
        end
    else
        self:Print("Export frame does not exist, creating")
        self:CreateExportFrame()
        self:Print("Now showing export frame")
        self.exportFrame:Show()
    end
end

function MailLogger:PrintHelp()
    self:Print("MailLogger commands:")
    self:Print("/maillog show - Display your mail item log")
    self:Print("/maillog export - Create copyable text of your log")
    self:Print("/maillog sum - Export with common items summed")
    self:Print("/maillog toggle - Show/hide the export pane")
    self:Print("/maillog auto - Toggle automatic export pane display")
    self:Print("/maillog summode - Toggle between regular and summed export")
    self:Print("/maillog clear - Clear your mail log")
    self:Print("/maillog debug - Toggle debug mode")
    self:Print("/maillog list - List characters with mail logs")
    self:Print("/maillog fix - Fix blank items in your log")
    self:Print("/maillog test - Test export pane display")
    self:Print("/maillog format - Toggle between detailed and inventory format")
    self:Print("/maillog help - Show this help message")
end

function MailLogger:ShowLog()
    if #self.itemLog == 0 then
        self:Print("Your mail log for " .. self.currentCharacter .. " is empty.")
        return
    end
    
    self:Print("Mail Item Log for " .. self.currentCharacter .. ":")
    for i, entry in ipairs(self.itemLog) do
        self:Print(string.format("%s: %s sent you %s %s", 
            entry.date, 
            entry.sender or "Unknown", 
            entry.count, 
            entry.itemName or "Unknown Item"))
    end
end

-- Function to fix blank item names in existing logs
function MailLogger:FixBlankItems()
    local fixedCount = 0
    local pendingCount = 0
    
    for i, entry in ipairs(self.itemLog) do
        -- Check if item name is missing or blank after cleaning
        local cleanName = entry.itemName and self:CleanTextForExport(entry.itemName) or "Unknown Item"
        
        if cleanName == "Unknown Item" then
            -- If we have an item ID, try to look it up
            if entry.itemID then
                local cachedName = self.itemCache[tostring(entry.itemID)]
                if cachedName then
                    -- Use the cached name
                    self.itemLog[i].itemName = cachedName
                    fixedCount = fixedCount + 1
                else
                    -- Set up a pending lookup
                    if not self.pendingItemLookups[entry.itemID] then
                        self.pendingItemLookups[entry.itemID] = {}
                    end
                    table.insert(self.pendingItemLookups[entry.itemID], {index = i})
                    pendingCount = pendingCount + 1
                end
            else
                -- No way to fix this entry
                fixedCount = fixedCount + 1
                self.itemLog[i].itemName = "Unknown Item"
            end
        end
    end
    
    -- Save the updated log
    self.db.char.itemLog = self.itemLog
    
    self:Print(string.format("Fixed %d blank item names. %d items queued for lookup.", fixedCount, pendingCount))
    
    -- Refresh the export frame if it's open
    self:RefreshExportFrame()
end

-- Create a summed version of the export data
function MailLogger:GetSummedItems()
    local summedItems = {}
    
    -- Group by sender and item name
    for _, entry in ipairs(self.itemLog) do
        local sender = entry.sender or "Unknown"
        local itemName = entry.itemName or "Unknown Item"
        local cleanItemName = self:CleanTextForExport(itemName)
        local count = entry.count
        
        -- Create a unique key for this sender+item combination
        local key = sender .. "|||" .. cleanItemName
        
        -- Special handling for gold
        if cleanItemName == "Gold" then
            -- Parse the gold, silver, copper values from the count
            local gold, silver, copper = 0, 0, 0
            
            if type(count) == "string" then
                -- Extract numeric values using more robust pattern matching
                -- This handles variations in spacing and formatting
                gold = tonumber(count:match("(%d+)%s*g")) or 0
                silver = tonumber(count:match("(%d+)%s*s")) or 0
                copper = tonumber(count:match("(%d+)%s*c")) or 0
                
                if self.debug then
                    self:Print("Debug: Parsed gold: " .. gold .. "g " .. silver .. "s " .. copper .. "c from: " .. count)
                end
            end
            
            -- Convert to total copper for summing
            local totalCopper = (gold * 10000) + (silver * 100) + copper
            
            if self.debug then
                self:Print("Debug: Converted to " .. totalCopper .. " copper")
            end
            
            if summedItems[key] then
                -- Add to existing gold
                local existingCopper = summedItems[key].copperValue or 0
                local newTotalCopper = existingCopper + totalCopper
                
                -- Update the count string
                local newGold = math.floor(newTotalCopper / 10000)
                local newSilver = math.floor((newTotalCopper % 10000) / 100)
                local newCopper = newTotalCopper % 100
                
                if self.debug then
                    self:Print("Debug: Updated gold sum for " .. sender .. ": " .. 
                               existingCopper .. " + " .. totalCopper .. " = " .. newTotalCopper .. 
                               " copper (" .. newGold .. "g " .. newSilver .. "s " .. newCopper .. "c)")
                end
                
                summedItems[key].count = newGold .. "g " .. newSilver .. "s " .. newCopper .. "c"
                summedItems[key].copperValue = newTotalCopper
                
                -- Update latest date if this entry is newer
                if entry.timestamp > summedItems[key].timestamp then
                    summedItems[key].date = entry.date
                    summedItems[key].timestamp = entry.timestamp
                end
            else
                -- Create new entry for gold
                if self.debug then
                    self:Print("Debug: New gold entry for " .. sender .. ": " .. count .. " (" .. totalCopper .. " copper)")
                end
                
                summedItems[key] = {
                    sender = sender,
                    itemName = cleanItemName,
                    count = count,
                    copperValue = totalCopper,
                    date = entry.date,
                    timestamp = entry.timestamp
                }
            end
        else
            -- Regular item handling (unchanged)
            local numCount = tonumber(count) or 0
            
            if summedItems[key] then
                -- Add to existing count
                summedItems[key].count = summedItems[key].count + numCount
                -- Update latest date if this entry is newer
                if entry.timestamp > summedItems[key].timestamp then
                    summedItems[key].date = entry.date
                    summedItems[key].timestamp = entry.timestamp
                end
            else
                -- Create new entry
                summedItems[key] = {
                    sender = sender,
                    itemName = cleanItemName,
                    count = numCount,
                    date = entry.date,
                    timestamp = entry.timestamp
                }
            end
        end
    end
    
    -- Convert to a sorted array
    local result = {}
    for _, item in pairs(summedItems) do
        table.insert(result, item)
    end
    
    -- Sort by sender name and then by item name
    table.sort(result, function(a, b)
        if a.sender == b.sender then
            return a.itemName < b.itemName
        else
            return a.sender < b.sender
        end
    end)
    
    return result
end

-- Create the export text in TSV (Tab-Separated Values) format
function MailLogger:CreateExportText(sumItems)

    -- If inventory format is enabled, use that instead
    if self.inventoryFormat then
        return self:CreateInventoryExportText()
    end

    local exportText = "MailLogger Export for " .. self.currentCharacter .. "\n"
    exportText = exportText .. "Date\tSender\tItem\tQuantity\n"
    
    -- Use either the summed data or raw data based on parameter
    local dataToExport = {}
    
    if sumItems then
        dataToExport = self:GetSummedItems()
    else
        for _, entry in ipairs(self.itemLog) do
            -- Get the data, only clean for export display 
            table.insert(dataToExport, {
                date = entry.date or "",
                sender = entry.sender or "Unknown",
                itemName = self:CleanTextForExport(entry.itemName or "Unknown Item"),
                count = entry.count or 0
            })
        end
    end
    
    -- Generate the export text
    for _, item in ipairs(dataToExport) do
        exportText = exportText .. string.format("%s\t%s\t%s\t%s\n", 
            item.date, item.sender, item.itemName, item.count)
    end
    
    return exportText
end

-- Create inventory format version of export data
function MailLogger:CreateInventoryExportText()
    -- Start with a header
    local exportText = "MailLogger Inventory Export for " .. self.currentCharacter .. "\n\n"
    
    -- Get the summed items grouped by sender and item
    local items = self:GetSummedItems()
    
    -- Group by sender first
    local senderGroups = {}
    for _, item in ipairs(items) do
        if not senderGroups[item.sender] then
            senderGroups[item.sender] = {}
        end
        table.insert(senderGroups[item.sender], {
            itemName = item.itemName,
            count = item.count,
            copperValue = item.copperValue -- Make sure we pass through the copper value
        })
    end
    
    -- Sort each sender's items by name
    for sender, itemsList in pairs(senderGroups) do
        table.sort(itemsList, function(a, b)
            return a.itemName < b.itemName
        end)
    end
    
    -- Create a sorted list of sender names
    local sortedSenders = {}
    for sender in pairs(senderGroups) do
        table.insert(sortedSenders, sender)
    end
    table.sort(sortedSenders)
    
    -- Generate the export text (grouped by sender)
    for _, sender in ipairs(sortedSenders) do
        -- Add sender header
        exportText = exportText .. "" .. sender .. ":\n"
        
        -- Add items from this sender
        for _, item in ipairs(senderGroups[sender]) do
            -- Special handling for Gold to use the g/s/c format
            if item.itemName == "Gold" then
                -- Use the pre-formatted string if available (which should include g/s/c)
                exportText = exportText .. string.format("  %s\n", item.count)
            else
                -- For regular items, use numeric format
                exportText = exportText .. string.format("  %d %s\n", 
                    item.count, item.itemName)
            end
        end
        
        -- Add a blank line between senders
        exportText = exportText .. "\n"
    end
    
    return exportText
end

-- Test export pane
function MailLogger:TestExportPane()
    -- Create test data similar to your example
    local testItems = {
        {date = date("%m/%d/%y"), sender = "Testplayer", itemName = "Flask of Petrification", count = 2},
        {date = date("%m/%d/%y"), sender = "Testplayer", itemName = "Elixir of Mongoose", count = 5},
        {date = date("%m/%d/%y"), sender = "Testplayer", itemName = "Oil of Immolation", count = 15},
        {date = date("%m/%d/%y"), sender = "Testplayer", itemName = "Sungrass", count = 60},
        {date = date("%m/%d/%y"), sender = "Testplayer", itemName = "Elixir of Greater Agility", count = 15}
    }
    
    -- Temporarily replace log with test data
    local originalLog = self.itemLog
    self.itemLog = testItems
    
    -- Show the export pane
    self:ShowExportPane()
    
    -- Restore original log
    self.itemLog = originalLog
end

-- Refresh export frame if it's open
function MailLogger:RefreshExportFrame()
    if self.exportFrame and self.exportFrame:IsShown() then
        -- Get updated export text based on current summed mode
        local exportText = self:CreateExportText(self.summedExport)
        
        -- Update the edit box and title
        if self.exportFrame.editBox then
            self.exportFrame.editBox:SetText(exportText)
            -- We don't automatically highlight text or focus when refreshing
            -- This prevents stealing focus from the mail frame
        end
        
        if self.exportFrame.title then
            self.exportFrame.title:SetText("MailLogger Export" .. 
                (self.summedExport and " (Summed)" or "") .. " - " .. self.currentCharacter)
        end

        -- Update format button
        if self.exportFrame.formatButton then
            self.exportFrame.formatButton:SetText(self.inventoryFormat and "Excel Format" or "Discord Format")
        end

            -- Update buttons
    if self.exportFrame.modeButton then
        self.exportFrame.modeButton:SetText(self.summedExport and "Show All Items" or "Show Summed")
        
        -- Disable summed button if inventory mode is enabled
        if self.inventoryFormat then
            self.exportFrame.modeButton:Disable()
            self.exportFrame.modeButton:SetText("Summed (Always On)")
        else
            self.exportFrame.modeButton:Enable()
            self.exportFrame.modeButton:SetText(self.summedExport and "Show All Items" or "Show Summed")
        end
    end

    end
end

-- Toggle whether to automatically show export pane
function MailLogger:ToggleAutoShow()
    self.autoShowExport = not self.autoShowExport
    self.db.profile.autoShowExport = self.autoShowExport
    
    self:Print("Auto-show export pane: " .. (self.autoShowExport and "ENABLED" or "DISABLED"))
end

-- Add function to toggle inventory format
function MailLogger:ToggleInventoryFormat()
    self.inventoryFormat = not self.inventoryFormat
    self.db.profile.inventoryFormat = self.inventoryFormat
    
    self:Print("Export format: " .. (self.inventoryFormat and "Discord Format" or "Excel Format"))
    
    -- Refresh if the pane is open
    self:RefreshExportFrame()
end

-- Toggle between regular and summed export mode
function MailLogger:ToggleSummedMode()
    self.summedExport = not self.summedExport
    self.db.profile.summedExport = self.summedExport
    
    self:Print("Export mode: " .. (self.summedExport and "SUMMED" or "REGULAR"))
    
    -- Refresh if the pane is open
    self:RefreshExportFrame()
end

-- Toggle showing/hiding the export pane
function MailLogger:ToggleExportPane()
    if self.exportFrame and self.exportFrame:IsShown() then
        self.exportFrame:Hide()
    else
        self:ShowExportPane()
    end
end

-- Export summed log function
function MailLogger:ExportSummedLog()
    self:ExportLog(true)
end

-- Standard export log function
function MailLogger:ExportLog(sumItems)
    if sumItems ~= nil then
        self.summedExport = sumItems
        self.db.profile.summedExport = self.summedExport
    end
    
    self:ShowExportPane()
end


-- Show the export pane
function MailLogger:ShowExportPane()
    self:Print("Showing export pane...")
    
    local frame = self:CreateExportFrame()
    
    -- Update content and show
    local exportText = self:CreateExportText(self.summedExport)
    frame.editBox:SetText(exportText)
    
    -- Update the title
    frame.title:SetText("MailLogger Export" .. 
        (self.summedExport and " (Summed)" or "") ..
        (self.inventoryFormat and " - Inventory Format" or "") ..
        " - " .. self.currentCharacter)
        
    -- Center the frame on screen each time it's shown
    -- This ensures it's centered even if a previous session moved it
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:Show()
    
    -- Update buttons
    if frame.modeButton then
        frame.modeButton:SetText(self.summedExport and "Show All Items" or "Show Summed")
        
        -- Disable summed button if inventory mode is enabled
        if self.inventoryFormat then
            frame.modeButton:Disable()
            frame.modeButton:SetText("Summed (Always On)")
        else
            frame.modeButton:Enable()
            frame.modeButton:SetText(self.summedExport and "Show All Items" or "Show Summed")
        end
    end
    
    self:Print("Export pane should now be visible")
end

-- Create the export frame once, then reuse it
function MailLogger:CreateExportFrame()
    if not self.exportFrame then
        -- Create a basic frame with increased width
        local frame = CreateFrame("Frame", "MailLoggerExportFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        frame:SetSize(500, 500) -- Increased width from 450 to 500
        
        -- Center the frame on the screen
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        
        -- Set backdrop (handle both pre and post Shadowlands API)
        if BackdropTemplateMixin then
            frame:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 32,
                insets = { left = 11, right = 12, top = 12, bottom = 11 }
            })
            frame:SetBackdropColor(0, 0, 0, 1)
        else
            -- For Classic
            local bg = frame:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0, 0, 0, 0.8)
            
            -- Add a border
            local border = CreateFrame("Frame", nil, frame)
            border:SetPoint("TOPLEFT", frame, "TOPLEFT", -2, 2)
            border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 2, -2)
            border:SetBackdrop({
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            })
            border:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
        end
        
        -- Make the frame movable
        frame:EnableMouse(true)
        frame:SetMovable(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        frame:SetFrameStrata("HIGH")
        
        -- Add a title text
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOP", 0, -15)
        title:SetText("MailLogger Export - " .. self.currentCharacter)
        frame.title = title
        
        -- Instructions
        local instructions = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        instructions:SetPoint("TOP", title, "BOTTOM", 0, -5)
        instructions:SetText("Click 'Copy' to select all text")
        
        -- Create a simple EditBox with increased width
        local editBox = CreateFrame("EditBox", "MailLoggerExportEditBox", frame)
        editBox:SetMultiLine(true)
        editBox:SetFontObject("ChatFontNormal")
        editBox:SetSize(450, 380) -- Increased width from 400 to 450
        editBox:SetPoint("TOP", instructions, "BOTTOM", 0, -10)
        editBox:SetAutoFocus(false) -- Important! Don't auto-focus
        editBox:SetScript("OnEscapePressed", function() 
            editBox:ClearFocus() 
            -- Safely try to return focus to mail frame
            self:SafeFocusMailFrame()
        end)
        frame.editBox = editBox
        
        -- Add a background texture to the EditBox
        local bg = editBox:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.1, 0.1, 0.1, 0.6)
        
        -- Define the confirmation dialog outside the button click handler
        StaticPopupDialogs["MAILLOGGER_CONFIRM_CLEAR"] = {
            text = "Are you sure you want to clear the mail log for " .. self.currentCharacter .. "?",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function()
                self:ClearLog()
                -- Return focus to mail frame if possible
                self:SafeFocusMailFrame()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        
        -- Create button container frame to hold all buttons in two rows
        local buttonContainer = CreateFrame("Frame", nil, frame)
        buttonContainer:SetSize(frame:GetWidth() - 40, 60) -- Taller to accommodate two rows
        buttonContainer:SetPoint("BOTTOM", 0, 15)
        
        -- Top row of buttons
        
        -- Mode toggle button (first button on top row)
        local modeButton = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
        modeButton:SetSize(120, 25)
        modeButton:SetPoint("TOPLEFT", 0, 0)
        modeButton:SetText(self.summedExport and "Show All Items" or "Show Summed")
        modeButton:SetScript("OnClick", function() 
            self:ToggleSummedMode()
            modeButton:SetText(self.summedExport and "Show All Items" or "Show Summed")
        end)
        frame.modeButton = modeButton

        -- Format toggle button (second button on top row)
        local formatButton = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
        formatButton:SetSize(120, 25)
        formatButton:SetPoint("LEFT", modeButton, "RIGHT", 10, 0)
        formatButton:SetText(self.inventoryFormat and "Excel Format" or "Discord Format")
        formatButton:SetScript("OnClick", function()
            self:ToggleInventoryFormat()
            formatButton:SetText(self.inventoryFormat and "Excel Format" or "Discord Format")
        end)
        frame.formatButton = formatButton
        
        -- Bottom row of buttons

        -- Clear button (first button on bottom row)
        local clearButton = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
        clearButton:SetSize(100, 25)
        clearButton:SetPoint("TOPLEFT", modeButton, "BOTTOMLEFT", 0, -10)
        clearButton:SetText("Clear Log")
        clearButton:SetScript("OnClick", function()
            StaticPopup_Show("MAILLOGGER_CONFIRM_CLEAR")
        end)
        frame.clearButton = clearButton
        
        -- Copy button (second button on bottom row)
        local copyButton = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
        copyButton:SetSize(100, 25)
        copyButton:SetPoint("LEFT", clearButton, "RIGHT", 10, 0)
        copyButton:SetText("Highlight")
        copyButton:SetScript("OnClick", function() 
            editBox:SetFocus()
            editBox:HighlightText()
        end)
    
        -- Close button (third button on bottom row)
        local closeButton = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
        closeButton:SetSize(100, 25)
        closeButton:SetPoint("LEFT", copyButton, "RIGHT", 10, 0)
        closeButton:SetText("Close")
        closeButton:SetScript("OnClick", function() 
            frame:Hide() 
            -- Safely try to return focus to mail frame
            self:SafeFocusMailFrame()
        end)
        
        self.exportFrame = frame
    end
    
    return self.exportFrame
end

function MailLogger:ClearLog()
    wipe(self.itemLog)
    self.db.char.itemLog = self.itemLog
    self:Print("Mail log for " .. self.currentCharacter .. " cleared.")
    
    -- Refresh the export frame if it's open
    self:RefreshExportFrame()
end

function MailLogger:ListCharacters()
    local count = 0
    self:Print("Characters with mail logs:")
    
    for charName, _ in pairs(self.db.global.characters) do
        count = count + 1
        if charName == self.currentCharacter then
            self:Print("  " .. charName .. " (current)")
        else
            self:Print("  " .. charName)
        end
    end
    
    if count == 0 then
        self:Print("  No character logs found.")
    end
end

function MailLogger:ToggleDebug()
    self.debug = not self.debug
    self:Print("Debug mode " .. (self.debug and "enabled" or "disabled"))
end

-- Override Print function to handle debug messages
local originalPrint = MailLogger.Print
function MailLogger:Print(msg)
    if self.debug or not msg:match("^Debug:") then
        originalPrint(self, msg)
    end
end