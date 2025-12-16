local DEBUG = false

local function tp_print(msg)
  if type(msg) == "boolean" then msg = msg and "true" or "false" end
  DEFAULT_CHAT_FRAME:AddMessage(msg)
end

local function debug_print(msg)
  if DEBUG then tp_print(msg) end
end

local L = "TankPlates"

-- stop loading addon if no superwow
if not SetAutoloot then
  DEFAULT_CHAT_FRAME:AddMessage("[|cff00ff00Tank|cffff0000Plates|r] requires |cffffd200SuperWoW|r to operate.")
  return
end
local HasUnitXP = pcall(UnitXP, "nop", "nop")
if not HasUnitXP then
	DEFAULT_CHAT_FRAME:AddMessage("[|cff00ff00Tank|cffff0000Plates|r] requires |cffffd200UnitXP|r to operate.")
	return
end

local player_guid = nil
local tracked_guids = {}


local function IsBehindUnit(guid)
  if not UnitExists(guid) then return false end
  return UnitXP("behind", "player", guid) == true
end
-- Copied from shagu since it resembled what I was trying to do anyway
-- [ HookScript ]
-- Securely post-hooks a script handler.
-- 'f'          [frame]             the frame which needs a hook
-- 'script'     [string]            the handler to hook
-- 'func'       [function]          the function that should be added
function HookScript(f, script, func)
  local prev = f:GetScript(script)
  f:SetScript(script, function(a1,a2,a3,a4,a5,a6,a7,a8,a9)
    if prev then prev(a1,a2,a3,a4,a5,a6,a7,a8,a9) end
    func(a1,a2,a3,a4,a5,a6,a7,a8,a9)
  end)
end

local function IsNamePlate(frame)
  local guid = frame:GetName(1)
  return frame and (frame:IsShown() and frame:IsObjectType("Button"))
    and (guid and guid ~= "0x0000000000000000")
    and (frame:GetChildren() and frame:GetChildren():IsObjectType("StatusBar"))
end

local function UpdateTarget(guid,targetArg)
  if not guid then return end
  local _, targeting = UnitExists(guid.."target")
  targeting = targetArg or targeting
  if targeting ~= tracked_guids[guid].current_target then
    -- only update previous target if there is a current one
    if tracked_guids[guid].current_target then
      tracked_guids[guid].previous_target = tracked_guids[guid].current_target
    end
    tracked_guids[guid].current_target = targeting
  end
end

local function InitPlate(plate)
  if plate.initialized then return end
  local guid = plate:GetName(1)

  for _, region in ipairs( { plate:GetRegions() } ) do
    if region:IsObjectType("FontString") and region:GetText() then
      local text = region:GetText()
      if not (tonumber(text) ~= nil or text == "??") then
        plate.namefontstring = region
      end
    end
  end

  if not plate.namefontstring then
    debug_print("tried to init a non-plate frame")
    return
  end

  HookScript(plate,"OnUpdate", function ()
    local guid = this:GetName(1)
    if not tracked_guids[guid] then
      debug_print("init loop hasn't grabbed this guid yet")
      return
    end
    tracked_guids[guid].tick = tracked_guids[guid].tick + arg1

    UpdateTarget(guid)

    -- behind check
    if tracked_guids[guid].tick > 0.1 then
      tracked_guids[guid].tick = 0
	   tracked_guids[guid].behind = IsBehindUnit(guid)
    end
  end)

  local origname = plate.namefontstring:GetText()
  local function UpdateHealth()
    local plate = this:GetParent()
    local guid = plate:GetName(1)
    if not guid then
      debug_print("plate didn't have guid?")
      return end
    if not tracked_guids[guid] then
      debug_print("plate init loop hasn't added this guid yet")
      return
    end
    local unit = tracked_guids[guid]

    if UnitIsUnit("target",guid) then
      -- plate.namefontstring:SetTextColor(1,0,1,1)
      plate.namefontstring:SetTextColor(1,1,0,1)
      -- plate.namefontstring:SetTextColor(0.825,0.144,0.825,1)
    else
      plate.namefontstring:SetTextColor(unpack(unit.unit_name_color))
    end

    if DEBUG then
      if unit.current_target then
        plate.namefontstring:SetText(UnitName(unit.current_target))
      else
        plate.namefontstring:SetText(origname)
      end
    end

    -- First, determine if this is a unit we should care to color.
    -- Is the player in combat, and is the unit in combat?
    -- if UnitAffectingCombat("player") and UnitAffectingCombat(guid) then
    if UnitAffectingCombat("player") and UnitAffectingCombat(guid) and
      not UnitCanAssist("player",guid) then -- don't color friendlies
      if unit.current_target == player_guid then
        -- attacking you
        this:SetStatusBarColor(0, 1, 0, 1) -- green
      elseif not unit.current_target and unit.previous_target == player_guid then
        -- fleeing but was attacking you
        this:SetStatusBarColor(0, 1, 0, 1) -- green
	  elseif unit.behind == false then 
			this:SetStatusBarColor(.35,1,1,1) --light blue
      else
        -- not attacking you
        this:SetStatusBarColor(1, 0, 0, 1) -- red
      end
    else
      this:SetStatusBarColor(unpack(unit.healthbar_color))
    end
  end

  HookScript(plate:GetChildren(), "OnUpdate", UpdateHealth)
  HookScript(plate:GetChildren(), "OnValueChanged", UpdateHealth)

  plate.initialized = true
end

local plateTick = 0
local cleanTick = 0
local function Update()
  plateTick = plateTick + arg1
  cleanTick = cleanTick + arg1
  if plateTick >= 0.075 then
    plateTick = 0 
    for _,plate in pairs({ WorldFrame:GetChildren() }) do
      if IsNamePlate(plate) then
        -- the plate can refer to a different unit constantly, check for new id's here and set the plate logic once
        -- to depend on its current guid
        InitPlate(plate)

        local guid = plate:GetName(1)
        if not tracked_guids[guid] then
          debug_print("adding "..guid.." "..UnitName(guid))
          -- store the original plate text color and health bar color, to revert to when needed
          tracked_guids[guid] = {
            unit_name_color = { plate.namefontstring:GetTextColor() },
            healthbar_color = { plate:GetChildren():GetStatusBarColor() },
            current_target = nil,
            previous_target = nil,
            tick = 0,
			behind = false,
          }
        end
      end
    end
  end
  if cleanTick > 10 then
    local count = 0
    cleanTick = 0
    for guid,_ in pairs(tracked_guids) do
      count = count + 1
      if not UnitExists(guid) then
        tracked_guids[guid] = nil
      end
    end
    debug_print("table size: "..count)
  end
end


local function Init()
  if event == "PLAYER_ENTERING_WORLD" then
    _,player_guid = UnitExists("player")
    this:SetScript("OnUpdate", Update)
    this:UnregisterEvent("PLAYER_ENTERING_WORLD")
  end
end

local tankplates = CreateFrame("Frame")
tankplates:SetScript("OnEvent", Init)
tankplates:RegisterEvent("PLAYER_ENTERING_WORLD")
