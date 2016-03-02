  -----------------------------------------------------------------------------------------------
-- Client Lua Script for OpenHouse
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------
 
require "Window"
require "string"
require "HousingLib"
 
-----------------------------------------------------------------------------------------------
-- OpenHouse Module Definition
-----------------------------------------------------------------------------------------------
local OpenHouse = {} 
 
-----------------------------------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------------------------------
-- e.g. local kiExampleVariableMax = 999
local kcrSelectedText = ApolloColor.new("UI_BtnTextHoloPressedFlyby")
local kcrNormalText = ApolloColor.new("UI_BtnTextHoloNormal")
local nWindowWitdthWithoutDetails = 742
local nWindowWitdthWithDetails = 1200 
local nRandomHousesSize= 25

--House Grid Columns
local sPlayerNameColumn = 1
local sPropertyNameColumn = 2
local sPlugsColumn = 3
local sNotesColumn = 4

-----------------------------------------------------------------------------------------------
-- Misc Items
-----------------------------------------------------------------------------------------------

local tHouseTemplate = {}

tHouseTemplate.prototype = {sPlayerName = "", sPropertyName = "", sPlugs = "", sNotes = ""}
tHouseTemplate.metaTable = {}
tHouseTemplate.metaTable.__index = tHouseTemplate.prototype

function tHouseTemplate.CreateNewHouse (tbl)
	setmetatable(tbl,tHouseTemplate.metaTable)
	return tbl
end

-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------
function OpenHouse:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self 

    -- initialize variables here
	o.tSelectedHouse = nil -- keep track of which list item is currently selected
	o.favHouses = {}
	o.tTempFavHouses = {}
	o.tRandomHouses = {}
	o.nRandomHouseLower = 1
	o.nRandomHouseUpper = nRandomHousesSize
	o.nCurrentRandomHouse = 1
	o.tRandomHouseTemp = {}
	o.bEnableButtons = "NA"
	o.tFormButtons ={}
	o.settings = {tAnchorPoints = {},
				 tAnchorOffsets = {},
				 showDetails = false
				 }
	o.settings.tAnchorPoints[1] = 0
	o.settings.tAnchorPoints[2] = 0
	o.settings.tAnchorPoints[3] = 0
	o.settings.tAnchorPoints[4] = 0
	
	o.settings.tAnchorOffsets [1] = 0
	o.settings.tAnchorOffsets [2] = 0
	o.settings.tAnchorOffsets [3] = nWindowWitdthWithoutDetails 
	o.settings.tAnchorOffsets [4] = 730
	
	o.settings.hasSaveTransitioned = false
	
    return o
end

function OpenHouse:Init()
	local bHasConfigureFunction = false
	local strConfigureButtonText = ""
	local tDependencies = {
		-- "UnitOrPackageName",
	}
    Apollo.RegisterAddon(self, bHasConfigureFunction, strConfigureButtonText, tDependencies)
	
end
 

-----------------------------------------------------------------------------------------------
-- OpenHouse OnLoad
-----------------------------------------------------------------------------------------------
function OpenHouse:OnLoad()
    -- load our form file
	self.xmlDoc = XmlDoc.CreateFromFile("OpenHouse.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
	
   -- self.contextMenu = Apollo.GetAddon("ContextMenuPlayer")
	--self:ContextMenuCheck()
	
end

-----------------------------------------------------------------------------------------------
-- OpenHouse OnDocLoaded
-----------------------------------------------------------------------------------------------
function OpenHouse:OnDocLoaded()

	if self.xmlDoc ~= nil and self.xmlDoc:IsLoaded() then
	    self.wndMain = Apollo.LoadForm(self.xmlDoc, "OpenHouseForm", nil, self)
		if self.wndMain == nil then
			Apollo.AddAddonErrorText(self, "Could not load the main window for some reason.")
			return
		end
		
	    self.wndMain:Show(false, true)

		-- if the xmlDoc is no longer needed, you should set it to nil
		-- self.xmlDoc = nil
		
		-- Register handlers for events, slash commands and timer, etc.
		-- e.g. Apollo.RegisterEventHandler("KeyDown", "OnKeyDown", self)
		Apollo.RegisterSlashCommand("oh", "OnOpenHouseOn", self)
		Apollo.RegisterSlashCommand("ohadd", "OnOpenHouseAdd", self)
		Apollo.RegisterSlashCommand("ohvisit", "OnOpenHouseVisit", self)
		Apollo.RegisterSlashCommand("ohhome", "OnOpenHouseGoHome", self)
		
		Apollo.RegisterEventHandler("HousingRandomResidenceListRecieved", "OnHousingRandomResidenceListRecieved", self)
		Apollo.RegisterEventHandler("GridDoubleClick", "OnGridDoubleClick", self)	
		Apollo.RegisterEventHandler("SubZoneChanged", "OnZoneChange", self)
		--Apollo.RegisterEventHandler("WindowManagementReady", "OnWindowManagementReady", self)
		Apollo.RegisterEventHandler("InterfaceMenuListHasLoaded", "OnInterfaceMenuListHasLoaded", self)
		Apollo.RegisterEventHandler("ToggleOpenHouse", "OnToggleOpenHouse", self)
	    --Apollo.RegisterEventHandler("TargetUnitChanged", "ContextMenuCheck", self)				
		-- Do additional Addon initialization here
		for k,v in pairs(self.favHouses) do
			setmetatable(self.favHouses[k],tHouseTemplate.metaTable)
		end
		
		self:FavHouseKeyCleanup()
	end
end

-----------------------------------------------------------------------------------------------
-- OpenHouse Functions
-----------------------------------------------------------------------------------------------
-- Define general functions here

-- on SlashCommand "/oh"

function OpenHouse:FavHouseKeyCleanup()
	for k,v in pairs(self.favHouses) do
		if k ~= string.lower(k) then
			local lowerKey = string.lower(k)
			self.favHouses[lowerKey] = v
			self.favHouses[k] = nil
		end
	end
end
function OpenHouse:OnOpenHouseOn()
	self:OnToggleOpenHouse()
	self:SendToRover("a",self.settings.hasSaveTransitioned)
end

function OpenHouse:OnOpenHouseAdd(strCommand, sInput)

	if sInput ~= "" then
		local input = {}
		local idx = 1
		
		for i in string.gmatch(sInput, '([^,]+)') do
			input[idx] = i
			idx = idx+1  
		end
		
		local sPlayerName = input[1] or ""
		local sNote = input[2] or ""

		self:AddHouseByName(sPlayerName, sNote)
		return
	end
	
	if HousingLib.IsHousingWorld() then
		self:OnFavCurrentHouse()
	end
end

function OpenHouse:OnOpenHouseVisit(strCommand, sInput)

	if sInput ~= "" and HousingLib.IsHousingWorld() then
		HousingLib.RequestVisitPlayer(sInput)
	end

end

function OpenHouse:OnOpenHouseGoHome()
	if HousingLib.IsHousingWorld() then
		HousingLib.RequestTakeMeHome()
	end
end



function OpenHouse:OnToggleOpenHouse()
	if self.wndMain:IsVisible() == false then
		self.wndMain:Invoke() -- show the window
		self:SetupMainForm()

		--set the property name if opened in residence
		self:SetCurrentPropertyAttributes()
		
		-- populate the item list
		self:PopulateHouseGrid()
		
		--Get a list of random houses. Done here to have them ready as doing it in the button sometimes tries to visit before getting a list
		HousingLib.RequestRandomResidenceList()	
		
		CopyTable(self.favHouses,self.tTempFavHouses)

	else
		self:OnCancel()
	end
end


--Wrapper for sending to rover
function OpenHouse:SendToRover(varName, varValue)
	Event_FireGenericEvent("SendVarToRover", varName, varValue)
end

--String trim
function OpenHouse.Trim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

function OpenHouse:IsPlayerFavorited(sPlayerName)
	
	if self.favHouses[sPlayerName] ~= nil then
		return true
	end
	
	return false
end

--Is it a valid name? Residence list sometimes returns garbage
function OpenHouse:IsPlayerNameGood(sNameToCheck)

	if #sNameToCheck <= 1 or not string.find(sNameToCheck,"%a") or string.byte(sNameToCheck) < 65
            or string.byte(sNameToCheck) > 122  then
		return false
	end
	
	return true
	
end

function CopyTable(from, to)
	if not from then return end
        to = to or {}
	for k,v in pairs(from) do
		to[k] = v
	end
        return to
end

--Add player/house to internal list and grid
function OpenHouse:AddFavHouse(house, shouldUpdateHouseDetails)
	
	local sPlayerName = string.lower(house.sPlayerName)

	if not self:IsPlayerFavorited(sPlayerName) then
	
		self.favHouses[sPlayerName] = house
		
		if shouldUpdateHouseDetails then
			self:SetCurrentPropertyAttributes()
			
		end
		
		self:AddItemToHouseGrid(self.favHouses[sPlayerName])
	else
		local currentHouseNotes = self.favHouses[sPlayerName].sNotes 
		if  currentHouseNotes ~= house.sNotes then
			self.favHouses[sPlayerName].sNotes = currentHouseNotes  .. " " .. house.sNotes
			if self.wndMain:IsVisible() then
				self:PopulateHouseGrid()
			end
		end	
	end
end

-- Used for visiting random houses. Will loop through 25 at a time (number returned by call to get randomresidences)
-- and if exceeds the 25 limit, will then get the next 25 to loop though. Table only holds 25 at a time so as to not unnecessarily
-- keep unused houses
function OpenHouse:OnHousingRandomResidenceListRecieved()

	if #self.tRandomHouses >= self.nRandomHouseUpper then
		return
	else
		local tRandomResidences = HousingLib.GetRandomResidenceList()
	
		for idx = 1, 25 do
			local currentResidence = tRandomResidences[idx]
			
			if self:IsPlayerNameGood(currentResidence.strCharacterName) then
				if #tRandomResidences < #self.tRandomHouses then
					local nextResidenceCount = #self.tRandomHouseTemp + 1		
					self.tRandomHouseTemp[nextResidenceCount] = currentResidence.strCharacterName				
				else
					local nextResidenceCount = #self.tRandomHouses 	+ 1		
					self.tRandomHouses[nextResidenceCount] = currentResidence.strCharacterName
				end
			end
		end
		
		HousingLib.RequestRandomResidenceList()
	end
end

--Set the property name of the house
function OpenHouse:OnZoneChange()

	self:SetCurrentPropertyAttributes()

	if self.wndMain:IsVisible() then
		self:ToggleEnableButtons()
		self:PopulateHouseGrid()
	end
	
end


--Sets the property name if in a favorited housing area
function OpenHouse:SetCurrentPropertyAttributes()
	
	if HousingLib.IsHousingWorld() then
		
		local tCurrentResidence = HousingLib.GetResidence()
		
		if tCurrentResidence then
		
			local sPropertyName = tCurrentResidence:GetPropertyName()
			local sPropertyOwner = string.lower(tCurrentResidence:GetPropertyOwnerName())
			
			if sPropertyOwner then
				if self.favHouses[sPropertyOwner] then
					--Player House Name
					if self.favHouses[sPropertyOwner].sPropertyName ~= sPropertyName then	
						self.favHouses[sPropertyOwner].sPropertyName = sPropertyName 
					end
		
					--Get Plots									
					local nPlotCount = tCurrentResidence:GetPlotCount()
					local tPlugs = {}
					local sPlugsConcat
					
					for idx=1, nPlotCount do
						local sPlugName = HousingLib.GetPlot(idx):GetPlugName() 
						
						if sPlugName then
							tPlugs[#tPlugs + 1] = sPlugName
						end
					end		
				
					sPlugsConcat= table.concat(tPlugs,", ")
					
					if self.favHouses[sPropertyOwner].sPlugs ~= sPlugsConcat then	
						self.favHouses[sPropertyOwner].sPlugs = sPlugsConcat 
					end
									
					local nSelectedRowNumber = self:GetSelectedGridRow("houseGrid")
					local sSelectedPlayer = self:GetSelectedPlayerFromGrid()

				end				
			end		
			
		end
	
	end
end


--Get the name of the property the player is currently at
function OpenHouse:GetCurrentPropertyName()	
	if HousingLib.IsHousingWorld() then
		return 	HousingLib.GetResidence():GetPropertyName()
	else
		return nil
	end
end

function OpenHouse:GetCurrentPropertyOwner()	
	if HousingLib.IsHousingWorld() then
		return 	HousingLib.GetResidence():GetPropertyOwnerName()
	else
		return nil
	end
end

function OpenHouse:OnWindowManagementReady()
    Event_FireGenericEvent("WindowManagementAdd", {wnd = self.wndMain, strName = "Open House"})
end


function OpenHouse:OnInterfaceMenuListHasLoaded()
	Event_FireGenericEvent("InterfaceMenuList_NewAddOn","Open House", {"ToggleOpenHouse", "", "IconSprites:Icon_MapNode_Map_PlayerHouse"})
end


-- Add an extra button to the player context menu
--[[function OpenHouse:ContextMenuCheck()
    local oldRedrawAll = self.contextMenu.RedrawAll
    
    self.contextMenu.RedrawAll = function(context)
        -- Check if right clicking on player
        if self.contextMenu.unitTarget == nil or self.contextMenu.unitTarget:IsACharacter() then
            if self.contextMenu.wndMain ~= nil then
                local wndButtonList = self.contextMenu.wndMain:FindChild("ButtonList")
                if wndButtonList ~= nil then
                    local wndNew = wndButtonList:FindChildByUserData("BtnOpenHouse")

                    if not wndNew then
                        wndNew = Apollo.LoadForm(self.contextMenu.xmlDoc, "BtnRegular", wndButtonList, self.contextMenu)
                        wndNew:SetData("BtnOpenHouse")
						wndNew:FindChild("BtnText"):SetText("OH - Save Player")
                    end
                end
            end
        end
        oldRedrawAll(context)
    end

    -- catch the event fired when the player clicks the context menu
    local oldContextClick = self.contextMenu.ProcessContextClick
    self.contextMenu.ProcessContextClick = function(context, eButtonType)
    if eButtonType == "BtnOpenHouse" then
     	local tOhHouse = tHouseTemplate.CreateNewHouse{sPlayerName = self.Trim(context.strTarget)}
		self:AddFavHouse(tOhHouse)
    end    

end]]


-----------------------------------------------------------------------------------------------
-- OpenHouse Grid Functions
-----------------------------------------------------------------------------------------------

--Grid double click
function OpenHouse:OnGridDoubleClick(wndHandler,wndControl,iRow,iCol)
	self:OnVisitPlayerHouse()
end

function OpenHouse:OnGridSelChanged(wndHandler,wndControl,iRow, iCol, iCurrRow, iCurrCol,bAllowChange)
	self.tSelectedHouse = self.favHouses[string.lower(self:GetSelectedPlayerFromGrid())]
		
	if not self.tSelectedHouse then
		local wnd = self.wndMain:FindChild("houseGrid")

		local nRow = iRow - 1
		
		if nRow and nRow > 0 then
			local sPlayerName = string.lower(wnd:GetCellText(nRow,sPlayerNameColumn))
			self.tSelectedHouse = self.favHouses[sPlayerName]
		end
	end
	
	if self.tSelectedHouse then
		self:SetDetailsPaneValues()
	else
		self:ClearDetailsPaneValues()
	end 
end

--Return player name from house grid
function OpenHouse:GetSelectedPlayerFromGrid()
	return self:GetSelectedGridItem("houseGrid",sPlayerNameColumn)
end

--Return selected row from Grid
function OpenHouse:GetSelectedGridRow(gridName)
	local wnd = self.wndMain:FindChild(gridName)
	
	if wnd then
		return wnd:GetCurrentRow()
	end 
end

--Get specific cell from selected row in grid
function OpenHouse:GetSelectedGridItem(gridName,colNumber)
		
		local wnd = self.wndMain:FindChild(gridName)
		
		local nCurrentRow = self:GetSelectedGridRow(gridName)
		
		if nCurrentRow then
			return wnd:GetCellText(nCurrentRow,colNumber)
		end
	
	return nil
end

-- populate house grid with saved houses
function OpenHouse:PopulateHouseGrid()
	-- make sure the item list is empty to start with
	self:DestroyGridItems()
	
	local idx = 1
	--Populate list from saved favorites
	for k,v in pairs(self.favHouses) do
		self:AddItemToHouseGrid(self.favHouses[k])
		idx = idx +1
	end
end

-- clear the grid
function OpenHouse:DestroyGridItems()
	-- destroy all the wnd inside the list
	local wnd  =  self.wndMain:FindChild("houseGrid")
	wnd:DeleteAll()
end


-- add an item into the item list
function OpenHouse:AddItemToHouseGrid(house)
	-- load the window item for the list item
	local wnd = self.wndMain:FindChild("houseGrid")
	if wnd then
		wnd:AddRow(house.sPlayerName)
		
		local latestRow = wnd:GetRowCount()
		
		wnd:SetCellText(latestRow, sPropertyNameColumn,house.sPropertyName)
		wnd:SetCellText(latestRow, sPlugsColumn,house.sPlugs)
		wnd:SetCellText(latestRow, sNotesColumn,house.sNotes)
		
	end
end

-----------------------------------------------------------------------------------------------
-- OpenHouseForm Functions
-----------------------------------------------------------------------------------------------
function OpenHouse:SetupMainForm()

	if self.settings.tAnchorPoints then
		self.wndMain:SetAnchorPoints(unpack(self.settings.tAnchorPoints))
	end
	if self.settings.tAnchorOffsets then
		self.wndMain:SetAnchorOffsets(unpack(self.settings.tAnchorOffsets))
	end
	
	self:ToggleDetailsButton(self.wndMain:FindChild("btnShowDetails"))
	self:ToggleEnableButtons()
end

--Sets colors and whether button is enabled based on whether your'e in housing instance
function OpenHouse:ToggleEnableButtons()
	
	local bOldEnabledSetting = self.bEnableButtons
	
	if HousingLib.IsHousingWorld() then
		self.bEnableButtons = true
	else
		self.bEnableButtons = false
	end

	if bOldEnabledSetting ~= self.bEnableButtons then
		local tFormButtons = self:GetMainFormButtons()
						
		if tFormButtons then
			for idx=1, #tFormButtons do
				tFormButtons[idx]:Enable(self.bEnableButtons)
		
				if  tFormButtons[idx]:GetName() == "btnGoHome" then
					if self.bEnableButtons then
						tFormButtons[idx]:SetBGColor(ApolloColor.new("UI_BtnBGDefault"))
					else
						tFormButtons[idx]:SetBGColor(ApolloColor.new("UI_BtnTextGrayDisabled"))
					end
				end
			end
		end 

	end	
end

--Loop through the controls on the main form and get buttons. Using name of control as can't find a way to identify the control as a button
function OpenHouse:GetMainFormButtons()
	local tMainWndChildren = self.wndMain:GetChildren()
	
	local tMainForm = {}
	
	if tMainWndChildren then
		for idx = 1, #tMainWndChildren do
			if tMainWndChildren[idx]:GetName() == "MainFormFrame" then
				tMainForm = tMainWndChildren[idx]
			end
		end
	end
	
	if tMainForm then
		local tMainFormControls = tMainForm:GetChildren()
		
		if tMainFormControls then
			local tFormButtons = {}
						
			for idx = 1, #tMainFormControls do
				local sControlName = tMainFormControls[idx]:GetName()
								
				if string.match(sControlName,"btn") then
					tFormButtons[#tFormButtons + 1] = tMainFormControls[idx]
				end
			end
			
			return tFormButtons
		end
	end		
end



-- when the OK button is clicked
function OpenHouse:OnOK()
	self.wndMain:Close() -- hide the window
end

-- when the Cancel button is clicked
function OpenHouse:OnCancel()
	self:DestroyGridItems()
	
	CopyTable(self.tTempFavHouses,self.favHouses)
	
	self.tTempFavHouses = nil
	
	self.wndMain:Close() -- hide the window
end

--Visit player button click
function OpenHouse:OnVisitPlayerHouse( wndHandler, wndControl, eMouseButton )
	local selectedPlayer  = self:GetSelectedPlayerFromGrid()
	
	if selectedPlayer then
		HousingLib.RequestVisitPlayer(selectedPlayer)
	end
	
end

-- Go Home button click
function OpenHouse:OnGoHomeSelected( wndHandler, wndControl, eMouseButton )
	self:OnOpenHouseGoHome()
end

-- Save current house butotn click
function OpenHouse:OnFavCurrentHouse( wndHandler, wndControl, eMouseButton, sNote)
	local tCurrentResidence = HousingLib.GetResidence()
	
	if tCurrentResidence then
		local houseOwner = string.lower(tCurrentResidence:GetPropertyOwnerName())
		local tOhHouse = tHouseTemplate.CreateNewHouse{sPlayerName =  houseOwner, sNotes = sNote or ""} 
	
		self:AddFavHouse(tOhHouse, true)
		
	end
end


-- Add House by name button click
function OpenHouse:OnAddHouseByName(wndHandler, wndControl, eMouseButton )
	local sPlayerName = wndControl:GetParent():FindChild("txtBoxPlayerName")
	
	if sPlayerName then
		self:AddHouseByName(sPlayerName:GetText())
		sPlayerName:SetText("")
	end
end

function OpenHouse:AddHouseByName(sPlayerName, sNote)

	if HousingLib.IsHousingWorld() and string.lower(self:GetCurrentPropertyOwner()) == self.Trim(string.lower(sPlayerName)) then
		self:OnFavCurrentHouse(nil,nil,nil, sNote)
	else
		local tOhHouse = tHouseTemplate.CreateNewHouse{sPlayerName = self.Trim(sPlayerName), sNotes = sNote}
		self:AddFavHouse(tOhHouse)
	end	
end

--Delete house button click
function OpenHouse:OnDeleteFavHouse( wndHandler, wndControl, eMouseButton )
	
	local wnd  =  self.wndMain:FindChild("houseGrid")
	
	local nCurrentRow = wnd:GetCurrentRow()
	
	if nCurrentRow then		
		local sSelectedPlayer = string.lower(self:GetSelectedPlayerFromGrid())
			
		if nCurrentRow then
			wnd:DeleteRow(nCurrentRow)
		end	
		
		if sSelectedPlayer then
			self.favHouses[sSelectedPlayer] = nil
		end
		
		self:ClearDetailsPaneValues()
		
		local nPrevRow = nCurrentRow - 1
		
		
	end

end

--Visit random house button click
function OpenHouse:OnVisitRandomHouse( wndHandler, wndControl, eMouseButton)

	self.nCurrentRandomHouse = self.nCurrentRandomHouse + 1	
	
	local houseToVisit = self.tRandomHouses[self.nCurrentRandomHouse]
	
	if self.nCurrentRandomHouse + 1 == self.nRandomHouseUpper  then
		
		HousingLib.RequestVisitPlayer(houseToVisit)
		self.nRandomHouseLower = self.nRanomHouseUpper + 1
		self.nRandomHouseUpper = self.nRandomHouseUpper + nRandomHousesSize
		
		HousingLib.RequestRandomResidenceList()
	else
		HousingLib.RequestVisitPlayer(houseToVisit)
	end	
end

--Show details pane button click
function OpenHouse:OnShowDetails(wndHandler, wndControl, eMouseButton)

	local oldShowDetails = self.settings.showDetails
	
	self.settings.showDetails = not self.settings.showDetails

	if oldShowDetails ~= self.settings.showDetails then
		self:ToggleWindowSizeForDetails(self.settings.showDetails)
		self:ToggleDetailsWindowEnabled(self.settings.showDetails)
	
		if self.settings.showDetails  then
			wndControl:ChangeArt("Crafting_CircuitSprites:btnCircuit_Holo_LeftArrow")
		else
			wndControl:ChangeArt("Crafting_CircuitSprites:btnCircuit_Holo_RightArrow")
		end
	end
end

function OpenHouse:ToggleDetailsButton(wndControl)
	if self.settings.showDetails  then
		wndControl:ChangeArt("Crafting_CircuitSprites:btnCircuit_Holo_LeftArrow")
	else
		wndControl:ChangeArt("Crafting_CircuitSprites:btnCircuit_Holo_RightArrow")
	end
end

-- Toggle the main form size if details should be shown or not
function OpenHouse:ToggleWindowSizeForDetails(bShowDetails)

	local x1,y1,x2,y2 = self.wndMain:GetAnchorOffsets();
	local widthToUse = nWindowWitdthWithoutDetails 
		
	if bShowDetails then
		widthToUse = nWindowWitdthWithDetails 
	end
	
	self.wndMain:SetAnchorOffsets(x1,y1,x1 + widthToUse ,y2);

end

--Enable/disable details pane
function OpenHouse:ToggleDetailsWindowEnabled(bShowDetails)
	local wnd = self.wndMain:FindChild("DetailsForm")
	wnd:Enable(bShowDetails)
end

function OpenHouse:OnSaveNote( wndHandler, wndControl, eMouseButton )
	local wnd = self.wndMain:FindChild("DetailsForm")
	
	local sNotesText = wnd:FindChild("txtPlayerNotes"):GetText()
	
	if self.tSelectedHouse then
		self.tSelectedHouse.sNotes = sNotesText
	
		local wnd = self.wndMain:FindChild("houseGrid")
		if wnd then
			local currentRow = wnd:GetCurrentRow()
			if currentRow then
				wnd:SetCellText(currentRow, sNotesColumn,sNotesText )
			end
		end

	end
		
end

function OpenHouse:OnWindowClosed( wndHandler, wndControl )
	self.settings.tAnchorPoints = {self.wndMain:GetAnchorPoints()}
	self.settings.tAnchorOffsets = {self.wndMain:GetAnchorOffsets()}
end

-----------------------------------------------------------------------------------------------
-- Details Pane
-----------------------------------------------------------------------------------------------

function OpenHouse:SetDetailsPaneValues()
	local wnd = self.wndMain:FindChild("DetailsForm")
		
	wnd:FindChild("txtPlayerName"):SetText(self.tSelectedHouse.sPlayerName)
	wnd:FindChild("txtPropertyName"):SetText(self.tSelectedHouse.sPropertyName)
	wnd:FindChild("txtPlugs"):SetText(self.tSelectedHouse.sPlugs)
	wnd:FindChild("txtPlayerNotes"):SetText(self.tSelectedHouse.sNotes)
end

function OpenHouse:ClearDetailsPaneValues()
	local wnd = self.wndMain:FindChild("DetailsForm")
	
	wnd:FindChild("txtPlayerName"):SetText("")
	wnd:FindChild("txtPropertyName"):SetText("")
	wnd:FindChild("txtPlugs"):SetText("")
	wnd:FindChild("txtPlayerNotes"):SetText("")
end

-----------------------------------------------------------------------------------------------
-- Save/Load
-----------------------------------------------------------------------------------------------
function OpenHouse:OnSave(eLevel)
	if  eLevel ~= GameLib.CodeEnumAddonSaveLevel.Realm and eLevel ~= GameLib.CodeEnumAddonSaveLevel.Character then return nil end
	
	if eLevel == GameLib.CodeEnumAddonSaveLevel.Realm then
		self.settings.tAnchorPoints = {self.wndMain:GetAnchorPoints()}
		self.settings.tAnchorOffsets = {self.wndMain:GetAnchorOffsets()}
				
		return {houses = CopyTable(self.favHouses), settings = CopyTable(self.settings)}
		
	elseif eLevel == GameLib.CodeEnumAddonSaveLevel.Character and not self.settings.hasSaveTransitioned then
		self.settings.hasSaveTransitioned = true
		return {houses = CopyTable(self.favHouses), settings = CopyTable(self.settings)}
	end
	
end

function OpenHouse:OnRestore(eLevel,tSaveData)
	if eLevel ~= GameLib.CodeEnumAddonSaveLevel.Realm and eLevel ~= GameLib.CodeEnumAddonSaveLevel.Character  then return end
	
	if tSaveData then
		if eLevel == GameLib.CodeEnumAddonSaveLevel.Character and tSaveData.settings.hasSaveTransitioned then
			self.settings.hasSaveTransitioned = true
		elseif  eLevel == GameLib.CodeEnumAddonSaveLevel.Character then
			self.favHouses = CopyTable(tSaveData.houses,self.favHouses) or {}
			self.settings = CopyTable(tSaveData.settings, self.settings) or {}
		elseif eLevel == GameLib.CodeEnumAddonSaveLevel.Realm then
			self.favHouses = CopyTable(tSaveData.houses,self.favHouses) or {}
			self.settings = CopyTable(tSaveData.settings, self.settings) or {}

		end		
	end
end

-----------------------------------------------------------------------------------------------
-- OpenHouse Instance
-----------------------------------------------------------------------------------------------
local OpenHouseInst = OpenHouse:new()
OpenHouseInst:Init()


