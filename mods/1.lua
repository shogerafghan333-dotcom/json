-- ============================================================
-- U5 综合菜单 v5.4（毛玻璃双面板 · 插画背景 · 开关式 · 两列网格 + 过渡动画）
-- 内透 / 绘制 / 范围 / 枪械 / 基本 / 自瞄
-- ============================================================

local GameplayData = require("GameLua.GameCore.Data.GameplayData")
local InGameMarkTools = require("GameLua.Mod.BaseMod.Common.InGameMarkTools")
local GamePlayTools = require("GameLua.Mod.BaseMod.Common.GamePlayTools")
local SecurityCommonUtils = require("GameLua.Mod.BaseMod.Common.Security.SecurityCommonUtils")
local ASTExtraPlayerController = import("/Script/ShadowTrackerExtra.STExtraPlayerController")

-- ============================================================
-- 自动保存系统
-- ============================================================
if not _G.ConfigAutoSave then
    _G.ConfigAutoSave = { Configs = {}, Started = false }
    local function GetTimerOwner()
        local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
        if slua.isValid(pc) then return pc, "pc" end
        return Game, "game"
    end
    local function ScheduleOnce(delay, cb)
        pcall(function()
            local owner, kind = GetTimerOwner()
            if kind == "pc" then owner:AddGameTimer(delay, false, cb)
            else Game:SetTimer(delay, false, cb) end
        end)
    end
    function _G.ConfigAutoSave:Register(name, configTable, paths, keyMapping)
        if type(paths) == "string" then paths = { paths } end
        self.Configs[name] = {
            Table = configTable, Paths = paths, CachedPath = nil,
            KeyMapping = keyMapping, Dirty = false, Scheduled = false, LastContent = ""
        }
    end
    function _G.ConfigAutoSave:MarkDirty(name)
        local cfg = self.Configs[name]
        if not cfg or cfg.Scheduled then return end
        cfg.Dirty = true
        cfg.Scheduled = true
        ScheduleOnce(2.0, function()
            cfg.Scheduled = false
            _G.ConfigAutoSave:Flush(name)
        end)
    end
    function _G.ConfigAutoSave:GenerateContent(name)
        local cfg = self.Configs[name]
        if not cfg then return "" end
        local lines = { "# 配置 - 自动生成" }
        for cfgKey, configKey in pairs(cfg.KeyMapping) do
            local v = cfg.Table[cfgKey]
            if type(v) == "boolean" then v = v and 1 or 0 end
            lines[#lines + 1] = configKey .. "=" .. tostring(v)
        end
        return table.concat(lines, "\n")
    end
    function _G.ConfigAutoSave:WriteToDisk(name, content)
        local cfg = self.Configs[name]
        if not cfg then return false end
        if cfg.CachedPath then
            local f
            pcall(function() f = io.open(cfg.CachedPath, "w") end)
            if f then f:write(content) f:close() return true end
            cfg.CachedPath = nil
        end
        for _, p in ipairs(cfg.Paths) do
            local f
            pcall(function() f = io.open(p, "w") end)
            if not f then
                pcall(function()
                    local dir = p:match("^(.*)/[^/]+$")
                    if dir and os and os.execute then os.execute('mkdir -p "' .. dir .. '"') end
                end)
                pcall(function() f = io.open(p, "w") end)
            end
            if f then f:write(content) f:close() cfg.CachedPath = p return true end
        end
        return false
    end
    function _G.ConfigAutoSave:Flush(name)
        local cfg = self.Configs[name]
        if not cfg or not cfg.Dirty then return end
        cfg.Dirty = false
        pcall(function()
            local content = _G.ConfigAutoSave:GenerateContent(name)
            if content == cfg.LastContent then return end
            if _G.ConfigAutoSave:WriteToDisk(name, content) then cfg.LastContent = content end
        end)
    end
    function _G.ConfigAutoSave:SaveAll()
        for name, _ in pairs(self.Configs) do self:Flush(name) end
    end
    function _G.ConfigAutoSave:LoadOne(name)
        local cfg = self.Configs[name]
        if not cfg then return end
        for _, p in ipairs(cfg.Paths) do
            local file
            pcall(function() file = io.open(p, "r") end)
            if file then
                pcall(function()
                    for line in file:lines() do
                        local trimmed = line:match("^%s*(.-)%s*$")
                        if trimmed and trimmed ~= "" and not trimmed:match("^#") then
                            local key, value = trimmed:match("^([^=]+)%s*=%s*(.+)$")
                            if key and value then
                                key = key:match("^%s*(.-)%s*$")
                                value = value:match("^%s*(.-)%s*$")
                                local num = tonumber(value)
                                if num ~= nil then
                                    for cfgKey, configKey in pairs(cfg.KeyMapping) do
                                        if configKey == key then cfg.Table[cfgKey] = num break end
                                    end
                                end
                            end
                        end
                    end
                end)
                file:close()
                cfg.CachedPath = p
                cfg.LastContent = self:GenerateContent(name)
                cfg.Dirty = false
                return
            end
        end
        cfg.Dirty = true
    end
    function _G.ConfigAutoSave:LoadAll()
        for name, _ in pairs(self.Configs) do self:LoadOne(name) end
    end
    function _G.ConfigAutoSave:StartLoop()
        if self.Started then return end
        self.Started = true
        self:LoadAll()
        local function SafetyNet()
            pcall(function() _G.ConfigAutoSave:SaveAll() end)
            ScheduleOnce(10.0, SafetyNet)
        end
        ScheduleOnce(10.0, SafetyNet)
    end
end

-- ============================================================
-- 路径
-- ============================================================
local GAME_PACKAGES = {
    "com.tencent.ig", "com.rekoo.pubgm", "com.pubg.krmobile",
    "com.pubg.imobile", "com.vng.pubgmobile",
}
local function MakePaths(fileName)
    local paths = {}
    for _, pkg in ipairs(GAME_PACKAGES) do
        table.insert(paths, "/storage/emulated/0/Android/data/" .. pkg .. "/" .. fileName)
    end
    for _, pkg in ipairs(GAME_PACKAGES) do
        table.insert(paths, "/storage/emulated/0/Android/data/" .. pkg ..
            "/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/" .. fileName)
    end
    table.insert(paths, "/Documents/ShadowTrackerExtra/Saved/Paks/" .. fileName)
    table.insert(paths, fileName)
    pcall(function()
        if os and os.getenv then
            local homeDir = os.getenv("HOME")
            if homeDir and homeDir ~= "" then
                table.insert(paths, 1, homeDir .. "/Documents/ShadowTrackerExtra/Saved/Paks/" .. fileName)
            end
        end
    end)
    return paths
end

-- ============================================================
-- 配置表
-- ============================================================
_G.U5Config = _G.U5Config or {
    GUN_RAINBOW=0,GUN_SINGLE_COLOR=0,GUN_THICKNESS=3,GUN_R=0,GUN_G=255,GUN_B=0,GUN_A=255,
    ENEMY_RAINBOW=0,ENEMY_SINGLE_COLOR=0,ENEMY_THICKNESS=1,ENEMY_R=0,ENEMY_G=255,ENEMY_B=0,ENEMY_A=255,
    COLOR_BRIGHTNESS=5,OUTLINE_SHOW_BOT=0,
    PLAYER_WALLHACK=0,DJ_VISIBLE_COLOR=2,DJ_HIDDEN_COLOR=1,DJ_SHOW_BOT=0,
}
_G.U5ESPConfig = _G.U5ESPConfig or {
    INFO_ESP=0,INFO_DISTANCE=200,INFO_SHOW_BOT=0,INFO_X=0,INFO_Y=0,INFO_Z=-100,INFO_FONT_SIZE=0.6,
    INFO_R=255,INFO_G=0,INFO_B=0,INFO_A=255,
    BOX_ESP=0,BOX_DISTANCE=100,BOX_FONT_SIZE=1.5,BOX_X=0,BOX_Y=0,BOX_Z=200,
    BOX_R=255,BOX_G=0,BOX_B=0,BOX_A=255,BOX_COUNT=10,BOX_SHOW_BOT=0,
    NATIVE_ESP=0,NATIVE_DISTANCE=250,NATIVE_SHOW_BOT=0,NATIVE_HP_BAR=0,NATIVE_FRAME=0,
    DIST_ESP=0,DIST_DISTANCE=200,DIST_SHOW_BOT=0,DIST_FONT_SIZE=0.6,DIST_X=0,DIST_Y=0,DIST_Z=-100,
    DIST_R=255,DIST_G=255,DIST_B=255,DIST_A=255,
}
_G.U5RangeConfig = _G.U5RangeConfig or {
    ENABLED=0, HEAD=0, NECK=0, PELVIS=0, SPINE=0,
    UPPERARM=0, LOWERARM=0, HAND=0, THIGH=0, CALF=0, FOOT=0,
}
_G.GunFuncConfig = _G.GunFuncConfig or {
    NO_RECOIL_ADS=0, ANTI_SHAKE=0, SUPER_FIRE_RATE=0, FIRE_RATE_VALUE=0.01,
    ALL_GUN_FOCUS=0, FOCUS_VALUE=0, QUICK_SCOPE=0, SCOPE_VALUE=25,
    QUICK_SWITCH=0, SWITCH_VALUE=0, EXTRA_HIT_SCALE=0,
}
_G.BasicFuncConfig = _G.BasicFuncConfig or {
    WIDE_ANGLE=0, TP_FOV=90, SCOPE_FOV=0,
    MEMORY_FOV=0, MEMORY_FOV_VALUE=120,
    LOCK_FPS=100, PERFORMANCE_OPT=0,
}
_G.AimBotConfig = _G.AimBotConfig or {
    ENABLED=0, HIP_AIM=0, FIRE_AIM=1, SCOPE_FIRE_AIM=1, SCOPE_AIM=0,
    AIM_BOT=0, WALL_CHECK=0, AIM_KNOCK=0,
    HIP_BONE=0, FIRE_BONE=0, SCOPE_FIRE_BONE=1, SCOPE_BONE=1,
    HIP_RECOIL=0, FIRE_RECOIL=0, SCOPE_FIRE_RECOIL=5,
    HIP_DIST=78, FIRE_DIST=78, SCOPE_FIRE_DIST=200, SCOPE_DIST=200,
    SCOPE_FIRE_NO_AIM_DIST=3, SCOPE_NO_AIM_DIST=3,
    HIP_FOV=20, FIRE_FOV=20, SCOPE_FIRE_FOV=8, SCOPE_FOV=8,
    HIP_SPEED=50, FIRE_SPEED=50, SCOPE_FIRE_SPEED=40, SCOPE_SPEED=40,
    AIM_PRIORITY=0,
    AIM_PREDICTION=0, PREDICTION_STRENGTH=30,
    PREDICTION_MAX_TIME=0.4, PREDICTION_SMOOTH=40,
    AIM_SNAP=1, AIM_SNAP_ANGLE=0.2, AIM_DEADZONE=0.06,
    PITCH_SPEED_FACTOR=1.0, TARGET_LOCK=1, LOCK_FOV_FACTOR=1.6,
    AIM_POINT_ADAPT=1, AIM_POINT_DIST=60,
    BULLET_DROP_COMP=1, BULLET_DROP_SCALE=100, BULLET_DROP_MIN_DIST=50, BULLET_SPEED=800,
    RECOIL_RAMP=1,
    FOV_CIRCLE=0, FOV_CIRCLE_COLOR=7, FOV_CIRCLE_THICKNESS=2,
    FOV_CIRCLE_MODE=0, FOV_CIRCLE_VIS_MODE=0,
    FOV_CIRCLE_VIS_COLOR=2, FOV_CIRCLE_COVER_COLOR=1,
}
_G.U5BtnConfig = _G.U5BtnConfig or { SHOW_FLOAT = 1 }

-- ============================================================
-- 自动保存注册
-- ============================================================
local AutoSaveSchemas = {
    { name="Wallhack", file="内透配置.h", cfg=_G.U5Config, map={
        ["GUN_RAINBOW"]="武器彩虹",["GUN_SINGLE_COLOR"]="武器单色",["GUN_THICKNESS"]="武器厚度",
        ["GUN_R"]="武器R",["GUN_G"]="武器G",["GUN_B"]="武器B",["GUN_A"]="武器A",
        ["ENEMY_RAINBOW"]="敌人彩虹",["ENEMY_SINGLE_COLOR"]="敌人单色",["ENEMY_THICKNESS"]="敌人厚度",
        ["ENEMY_R"]="敌人R",["ENEMY_G"]="敌人G",["ENEMY_B"]="敌人B",["ENEMY_A"]="敌人A",
        ["COLOR_BRIGHTNESS"]="颜色亮度",["OUTLINE_SHOW_BOT"]="轮廓显示人机",
        ["PLAYER_WALLHACK"]="人物内透",["DJ_VISIBLE_COLOR"]="可见颜色",
        ["DJ_HIDDEN_COLOR"]="遮挡颜色",["DJ_SHOW_BOT"]="人物内透显示人机",
    }},
    { name="ESP", file="绘制配置.h", cfg=_G.U5ESPConfig, map={
        ["INFO_ESP"]="武器信息",["INFO_DISTANCE"]="信息距离",["INFO_SHOW_BOT"]="信息人机",
        ["INFO_X"]="信息X",["INFO_Y"]="信息Y",["INFO_Z"]="信息Z",
        ["INFO_FONT_SIZE"]="信息字体",["INFO_R"]="信息R",["INFO_G"]="信息G",
        ["INFO_B"]="信息B",["INFO_A"]="信息A",
        ["BOX_ESP"]="盒子开关",["BOX_DISTANCE"]="盒子距离",["BOX_FONT_SIZE"]="盒子字体",
        ["BOX_X"]="盒子X",["BOX_Y"]="盒子Y",["BOX_Z"]="盒子Z",
        ["BOX_R"]="盒子R",["BOX_G"]="盒子G",["BOX_B"]="盒子B",["BOX_A"]="盒子A",
        ["BOX_COUNT"]="盒子数量",["BOX_SHOW_BOT"]="盒子人机",
        ["NATIVE_ESP"]="原生开关",["NATIVE_DISTANCE"]="原生距离",["NATIVE_SHOW_BOT"]="原生人机",
        ["NATIVE_HP_BAR"]="血条",["NATIVE_FRAME"]="方框",
        ["DIST_ESP"]="距离开关",["DIST_DISTANCE"]="距离距离",["DIST_SHOW_BOT"]="距离人机",
        ["DIST_FONT_SIZE"]="距离字体",["DIST_X"]="距离X",["DIST_Y"]="距离Y",["DIST_Z"]="距离Z",
        ["DIST_R"]="距离R",["DIST_G"]="距离G",["DIST_B"]="距离B",["DIST_A"]="距离A",
    }},
    { name="Range", file="范围配置.h", cfg=_G.U5RangeConfig, map={
        ["ENABLED"]="启用",["HEAD"]="头部",["NECK"]="脖子",["PELVIS"]="骨盆",["SPINE"]="脊椎",
        ["UPPERARM"]="上臂",["LOWERARM"]="前臂",["HAND"]="手部",
        ["THIGH"]="大腿",["CALF"]="小腿",["FOOT"]="脚部",
    }},
    { name="GunFunc", file="枪械配置.h", cfg=_G.GunFuncConfig, map={
        ["NO_RECOIL_ADS"]="无后座",["ANTI_SHAKE"]="防抖",
        ["SUPER_FIRE_RATE"]="超快射速",["FIRE_RATE_VALUE"]="射速值",
        ["ALL_GUN_FOCUS"]="全枪聚点",["FOCUS_VALUE"]="聚点值",
        ["QUICK_SCOPE"]="秒开镜",["SCOPE_VALUE"]="开镜速度",
        ["QUICK_SWITCH"]="快速切枪",["SWITCH_VALUE"]="切枪速度",
        ["EXTRA_HIT_SCALE"]="X特效",
    }},
    { name="BasicFunc", file="基本功能配置.h", cfg=_G.BasicFuncConfig, map={
        ["WIDE_ANGLE"]="广角",["TP_FOV"]="第三人称视野",["SCOPE_FOV"]="开镜视野",
        ["MEMORY_FOV"]="内存广角",["MEMORY_FOV_VALUE"]="内存广角值",
        ["LOCK_FPS"]="锁帧",["PERFORMANCE_OPT"]="性能优化",
    }},
    { name="AimBot", file="U5保存.h", cfg=_G.AimBotConfig, map={
        ["ENABLED"]="自瞄",["HIP_AIM"]="腰射自瞄",["FIRE_AIM"]="开火自瞄",
        ["SCOPE_FIRE_AIM"]="开镜开火自瞄",["SCOPE_AIM"]="开镜自瞄",
        ["AIM_BOT"]="显示人机",["WALL_CHECK"]="不自瞄掩体",["AIM_KNOCK"]="自瞄倒地",
        ["HIP_BONE"]="腰射部位",["FIRE_BONE"]="开火部位",
        ["SCOPE_FIRE_BONE"]="开镜开火部位",["SCOPE_BONE"]="开镜部位",
        ["HIP_RECOIL"]="腰射压枪值",["FIRE_RECOIL"]="开火压枪值",
        ["SCOPE_FIRE_RECOIL"]="开镜开火压枪值",
        ["HIP_DIST"]="腰射自瞄距离",["FIRE_DIST"]="开火自瞄距离",
        ["SCOPE_FIRE_DIST"]="开镜开火自瞄距离",["SCOPE_DIST"]="开镜自瞄距离",
        ["SCOPE_FIRE_NO_AIM_DIST"]="开镜开火不自瞄距离",["SCOPE_NO_AIM_DIST"]="开镜不自瞄距离",
        ["HIP_FOV"]="腰射范围",["FIRE_FOV"]="开火范围",
        ["SCOPE_FIRE_FOV"]="开镜开火范围",["SCOPE_FOV"]="开镜范围",
        ["HIP_SPEED"]="腰射速度",["FIRE_SPEED"]="开火速度",
        ["SCOPE_FIRE_SPEED"]="开镜开火速度",["SCOPE_SPEED"]="开镜速度",
        ["AIM_PRIORITY"]="自瞄优先级",["AIM_PREDICTION"]="自瞄预判",
        ["PREDICTION_STRENGTH"]="预判强度",["PREDICTION_MAX_TIME"]="预判最大时间",
        ["PREDICTION_SMOOTH"]="速度平滑",["AIM_SNAP"]="近距离吸附",
        ["AIM_SNAP_ANGLE"]="吸附阈值",["AIM_DEADZONE"]="死区角度",
        ["PITCH_SPEED_FACTOR"]="垂直速度系数",["TARGET_LOCK"]="目标锁定",
        ["LOCK_FOV_FACTOR"]="锁定FOV放宽",["AIM_POINT_ADAPT"]="距离自适应部位",
        ["AIM_POINT_DIST"]="自适应部位距离",["BULLET_DROP_COMP"]="弹道补偿",
        ["BULLET_DROP_SCALE"]="弹道补偿强度",["BULLET_DROP_MIN_DIST"]="弹道补偿最小距离",
        ["BULLET_SPEED"]="子弹速度",["RECOIL_RAMP"]="压枪递增",
        ["FOV_CIRCLE"]="显示FOV圈",["FOV_CIRCLE_COLOR"]="FOV圈颜色",
        ["FOV_CIRCLE_THICKNESS"]="FOV圈粗细",["FOV_CIRCLE_MODE"]="FOV圈模式",
        ["FOV_CIRCLE_VIS_MODE"]="FOV圈掩体变色",["FOV_CIRCLE_VIS_COLOR"]="FOV圈可见颜色",
        ["FOV_CIRCLE_COVER_COLOR"]="FOV圈遮挡颜色",
    }},
    { name="U5Btn", file="U5按钮配置.h", cfg=_G.U5BtnConfig, map={
        ["SHOW_FLOAT"] = "显示左上角 U5 浮动按钮",
    }},
}
local function InitAutoSave()
    for _, s in ipairs(AutoSaveSchemas) do
        _G.ConfigAutoSave:Register(s.name, s.cfg, MakePaths(s.file), s.map)
    end
end
local function LoadConfig()
    if _G.ConfigAutoSave then
        for _, s in ipairs(AutoSaveSchemas) do _G.ConfigAutoSave:LoadOne(s.name) end
    end
end
local function SaveConfigU5Btn()
    if _G.ConfigAutoSave then _G.ConfigAutoSave:MarkDirty("U5Btn") end
end

-- ============================================================
-- 基础工具
-- ============================================================
local function Valid(obj) return slua.isValid(obj) end
local function IsAI(pawn) return (pawn.TeamID or 0) > 100 end
local function IsAlive(pawn)
    if not Valid(pawn) then return false end
    local alive = false
    pcall(function() alive = pawn:IsAlive() end)
    return alive
end
local function GetLocalPlayer() return GameplayData.GetPlayerCharacter() end
local function Clamp(val, min, max)
    if val < min then return min end
    if val > max then return max end
    return val
end
local function IsDowned(pawn)
    if not Valid(pawn) then return false end
    return (pawn.HealthStatus or 0) == 1
end
local function IsDeadBox(pawn)
    local name = pawn.PlayerName or ""
    return name == "" or name == "Unknown" or name == "UNKNOWN"
end
local function GetWeaponName(tPawn)
    local weapon = tPawn.CurrentWeapon or (tPawn.GetCurrentWeapon and tPawn:GetCurrentWeapon())
    if weapon and Valid(weapon) then
        return weapon.GetWeaponName and weapon:GetWeaponName() or "武器"
    end
    return "手"
end
local function GetDistance(p1, p2)
    local a = p1:K2_GetActorLocation()
    local b = p2:K2_GetActorLocation()
    if not a or not b then return 999999 end
    local dx = a.X - b.X
    local dy = a.Y - b.Y
    local dz = a.Z - b.Z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end
local function IsPawnAlive2(p)
    if not Valid(p) then return false end
    if p.IsAlive then
        local alive = false
        pcall(function() alive = p:IsAlive() end)
        if not alive then return false end
    end
    if p.Health and p.Health <= 0 then return false end
    if p.HealthStatus and not SecurityCommonUtils.IsHealthStatusAlive(p.HealthStatus) then return false end
    if p.bIsDead ~= nil and p.bIsDead then return false end
    return true
end

-- ============================================================
-- 内透
-- ============================================================
local RainbowHue = 0
local function HueToRGB(hue, saturation, value)
    if not saturation then saturation = 1 end
    if not value then value = _G.U5Config.COLOR_BRIGHTNESS end
    local i = math.floor(hue * 6)
    local f = hue * 6 - i
    local p = value * (1 - saturation)
    local q = value * (1 - f * saturation)
    local t = value * (1 - (1 - f) * saturation)
    i = i % 6
    if i == 0 then return value, t, p
    elseif i == 1 then return q, value, p
    elseif i == 2 then return p, value, t
    elseif i == 3 then return p, q, value
    elseif i == 4 then return t, p, value
    else return value, p, q end
end
local function GetRainbowColor(brightness)
    brightness = brightness or _G.U5Config.COLOR_BRIGHTNESS
    RainbowHue = RainbowHue + 0.05
    if RainbowHue >= 1 then RainbowHue = 0 end
    local r, g, b = HueToRGB(RainbowHue, 1, brightness)
    return FLinearColor(r, g, b, 1)
end
local function GetSingleColor(r, g, b, a, brightness)
    brightness = brightness or _G.U5Config.COLOR_BRIGHTNESS
    local scale = brightness / 1.8
    return FLinearColor((r/255)*scale, (g/255)*scale, (b/255)*scale, a/255)
end

local meshCache = {}
local function GetAllMeshes(pawn)
    if not Valid(pawn) then return {} end
    local cached = meshCache[pawn]
    if cached then return cached end
    local all = {}
    pcall(function()
        if Valid(pawn.Mesh) then table.insert(all, pawn.Mesh) end
        if Valid(pawn.CharacterMesh0) then table.insert(all, pawn.CharacterMesh0) end
        if Valid(pawn.SkeletalMesh) then table.insert(all, pawn.SkeletalMesh) end
    end)
    if #all == 0 then
        pcall(function()
            local skelClass = import("SkeletalMeshComponent")
            if skelClass then
                local comps = pawn:GetComponentsByClass(skelClass)
                if comps then
                    for i = 0, comps:Num() - 1 do
                        local c = comps:Get(i)
                        if Valid(c) then table.insert(all, c) end
                    end
                end
            end
        end)
    end
    meshCache[pawn] = all
    return all
end

local function ApplyOutline(pawn, color, thickness)
    if not Valid(pawn) then return end
    for _, mesh in ipairs(GetAllMeshes(pawn)) do
        if Valid(mesh) and mesh.SetDrawIdeaOutline then
            pcall(function()
                mesh:SetDrawIdeaOutline(true)
                if color and mesh.OverrideIdeaOutlineColor then
                    mesh:OverrideIdeaOutlineColor(true, color)
                end
                if mesh.OverrideIdeaOutlineThickness then
                    mesh:OverrideIdeaOutlineThickness(true, thickness)
                end
            end)
        end
    end
end
local function ClearOutline(pawn)
    if not Valid(pawn) then return end
    for _, mesh in ipairs(GetAllMeshes(pawn)) do
        if Valid(mesh) and mesh.SetDrawIdeaOutline then
            pcall(function() mesh:SetDrawIdeaOutline(false) end)
        end
    end
end

local outlineState = {}
local function UpdateOutlines()
    local cfg = _G.U5Config
    local char = GetLocalPlayer()
    if not Valid(char) then return end
    local myKey = char.PlayerKey

    local wm = char:GetWeaponManager()
    if Valid(wm) then
        local gunMode = 0
        local gcol = nil
        if cfg.GUN_RAINBOW == 1 or cfg.GUN_SINGLE_COLOR == 1 then
            gunMode = cfg.GUN_RAINBOW == 1 and 1 or 2
            gcol = cfg.GUN_SINGLE_COLOR == 1 and
                GetSingleColor(cfg.GUN_R, cfg.GUN_G, cfg.GUN_B, cfg.GUN_A) or
                GetRainbowColor()
        end
        local gunHash = gunMode == 2 and
            (cfg.GUN_R.."_"..cfg.GUN_G.."_"..cfg.GUN_B.."_"..cfg.GUN_A.."_"..cfg.GUN_THICKNESS) or nil
        for slot = 0, 10 do
            local w = wm:GetInventoryWeaponByPropSlot(slot)
            if Valid(w) then
                local key = w
                local st = outlineState[key]
                if gunMode == 1 then
                    ApplyOutline(w, gcol, cfg.GUN_THICKNESS)
                    outlineState[key] = { mode = 1 }
                elseif gunMode == 2 then
                    if not (st and st.mode == 2 and st.hash == gunHash) then
                        ApplyOutline(w, gcol, cfg.GUN_THICKNESS)
                        outlineState[key] = { mode = 2, hash = gunHash }
                    end
                else
                    if st and st.mode ~= 0 then ClearOutline(w) end
                    outlineState[key] = { mode = 0 }
                end
            end
        end
    end

    local myTeamId = char.TeamID or 0
    local allPawns = Game:GetAllPlayerPawns() or {}
    local enemyMode = 0
    local ecol = nil
    if cfg.ENEMY_RAINBOW == 1 or cfg.ENEMY_SINGLE_COLOR == 1 then
        enemyMode = cfg.ENEMY_RAINBOW == 1 and 1 or 2
        ecol = cfg.ENEMY_SINGLE_COLOR == 1 and
            GetSingleColor(cfg.ENEMY_R, cfg.ENEMY_G, cfg.ENEMY_B, cfg.ENEMY_A) or
            GetRainbowColor()
    end
    local enemyHash = enemyMode == 2 and
        (cfg.ENEMY_R.."_"..cfg.ENEMY_G.."_"..cfg.ENEMY_B.."_"..cfg.ENEMY_A.."_"..cfg.ENEMY_THICKNESS) or nil
    for _, p in pairs(allPawns) do
        if Valid(p) and p.PlayerKey ~= myKey then
            local key = p.PlayerKey or p
            local st = outlineState[key]
            local isEnemy = p.TeamID ~= myTeamId and IsAlive(p)
            if isEnemy and cfg.OUTLINE_SHOW_BOT == 0 and IsAI(p) then isEnemy = false end
            if enemyMode == 1 then
                if isEnemy then
                    ApplyOutline(p, ecol, cfg.ENEMY_THICKNESS)
                    outlineState[key] = { mode = 1 }
                elseif st and st.mode ~= 0 then
                    ClearOutline(p)
                    outlineState[key] = { mode = 0 }
                end
            elseif enemyMode == 2 then
                if isEnemy then
                    if not (st and st.mode == 2 and st.hash == enemyHash) then
                        ApplyOutline(p, ecol, cfg.ENEMY_THICKNESS)
                        outlineState[key] = { mode = 2, hash = enemyHash }
                    end
                elseif st and st.mode ~= 0 then
                    ClearOutline(p)
                    outlineState[key] = { mode = 0 }
                end
            else
                if st and st.mode ~= 0 then ClearOutline(p) end
                outlineState[key] = { mode = 0 }
            end
        end
    end
end

local DJWallV3 = {}
do
    local KismetSystemLibrary = import("KismetSystemLibrary")
    local LinearColor = import("LinearColor")
    local CONSOLE_READY = false
    local APPLIED_PAWNS = {}
    local APPLIED_VER = -1
    local PER_TICK_LIMIT = 5
    local AVATAR_SLOTS = {0,1,2,3,4,5,6,7}

    local function GetColorByIndex(idx)
        if idx == 1 then return LinearColor(100, 0, 0, 1) end
        if idx == 2 then return LinearColor(0, 100, 0, 1) end
        if idx == 3 then return LinearColor(0, 0, 100, 1) end
        if idx == 4 then return LinearColor(100, 100, 0, 1) end
        if idx == 5 then return LinearColor(100, 0, 100, 1) end
        if idx == 6 then return LinearColor(0, 100, 100, 1) end
        return LinearColor(0, 100, 0, 1)
    end
    local function SetupConsole()
        if CONSOLE_READY then return end
        pcall(function()
            local world = slua.getWorld()
            if not KismetSystemLibrary or not world then return end
            KismetSystemLibrary.ExecuteConsoleCommand(world, "r.EnableDrawDyeingColor 1")
            KismetSystemLibrary.ExecuteConsoleCommand(world, "r.CustomDepth 3")
            KismetSystemLibrary.ExecuteConsoleCommand(world, "r.IdeaOutline.Enable 1")
            KismetSystemLibrary.ExecuteConsoleCommand(world, "r.Highlight.Enable 1")
            CONSOLE_READY = true
        end)
    end
    local function ApplyToMesh(mesh, visColor, occColor)
        if not mesh or not slua.isValid(mesh) then return end
        pcall(function()
            mesh:SetDrawDyeing(true)
            mesh:SetDrawDyeingMode(1)
            mesh:SetVisibleDyeingColor(visColor)
            mesh:SetOccludedDyeingColor(occColor)
            mesh:SetDyeingColorFadeDistance(99999.0)
            mesh:SetDyeingColorMinMaxDistance(0.0, 99999.0)
            mesh:SetDrawHighlight(true)
            mesh:OverrideHighlightColor(visColor)
            mesh:SetHighlightCanBeOccluded(false)
            mesh:SetDrawIdeaOutline(true)
            mesh:SetIdeaOutlineNew(true)
            mesh:SetIdeaOutlineOcclusionHighlight(true)
            mesh:OverrideIdeaOutlineColor(visColor)
            mesh:SetIdeaOutlineOcclusionColor(occColor)
            mesh:OverrideIdeaOutlineThickness(20.0)
            mesh:SetIdeaOverrideOutlineAndOcclusion(true)
            mesh:SetRenderCustomDepth(true)
            mesh:SetCustomDepthStencilValue(255)
        end)
    end
    local function IsPawnAlive(pawn)
        if not slua.isValid(pawn) then return false end
        return pawn.Health and pawn.Health > 0
    end
    function DJWallV3.DJWallhack()
        if _G.U5Config.PLAYER_WALLHACK ~= 1 then return end
        pcall(function()
            local localPawn = GameplayData.GetPlayerCharacter()
            if not slua.isValid(localPawn) then return end
            SetupConsole()
            local cfg = _G.U5Config
            local visColorIdx = cfg.DJ_VISIBLE_COLOR or 2
            local occColorIdx = cfg.DJ_HIDDEN_COLOR or 1
            local showBot = cfg.DJ_SHOW_BOT or 0
            local cfgKey = visColorIdx * 10 + occColorIdx + (showBot == 1 and 100 or 0)
            if cfgKey ~= APPLIED_VER then
                APPLIED_VER = cfgKey
                APPLIED_PAWNS = {}
            end
            local myTeamId = localPawn.TeamID or 0
            local allPawns = Game:GetAllPlayerPawns() or {}
            local processedCount = 0
            local baseVisColor = GetColorByIndex(visColorIdx)
            local baseOccColor = GetColorByIndex(occColorIdx)
            for _, pawn in pairs(allPawns) do
                if processedCount >= PER_TICK_LIMIT then break end
                if slua.isValid(pawn) and pawn ~= localPawn then
                    local key = pawn.PlayerKey
                    local applied = key and APPLIED_PAWNS[key]
                    if not (applied and applied == cfgKey) then
                        if not (IsAI(pawn) and showBot ~= 1) then
                            if IsPawnAlive(pawn) and pawn.TeamID and pawn.TeamID ~= myTeamId then
                                pcall(function()
                                    if slua.isValid(pawn.Mesh) then
                                        ApplyToMesh(pawn.Mesh, baseVisColor, baseOccColor)
                                    end
                                    local avatarComp = pawn.CharacterAvatarComp2_BP or
                                        pawn:getAvatarComponent2()
                                    if avatarComp and avatarComp.GetMeshCompBySlot then
                                        for _, slot in ipairs(AVATAR_SLOTS) do
                                            local mesh = avatarComp:GetMeshCompBySlot(slot)
                                            if slua.isValid(mesh) then
                                                ApplyToMesh(mesh, baseVisColor, baseOccColor)
                                            end
                                        end
                                    end
                                    local weapon = pawn:GetCurrentWeapon()
                                    if slua.isValid(weapon) and slua.isValid(weapon.Mesh) then
                                        ApplyToMesh(weapon.Mesh, baseVisColor, baseOccColor)
                                    end
                                end)
                                if key then APPLIED_PAWNS[key] = cfgKey end
                                processedCount = processedCount + 1
                            end
                        end
                    end
                end
            end
        end)
    end
end

-- ============================================================
-- 绘制
-- ============================================================
local cachedHUD, cachedHUDValid = nil, false
local function GetHUD()
    if cachedHUDValid and Valid(cachedHUD) then return cachedHUD end
    local controller = slua_GameFrontendHUD:GetPlayerController()
    if not Valid(controller) then return nil end
    local hud = controller:GetHUD()
    if Valid(hud) then
        cachedHUD, cachedHUDValid = hud, true
        return hud
    end
    cachedHUDValid = false
    return nil
end

local infoCachedEnemies, infoLastRefresh = {}, 0
local function GetValidEnemiesInfo(character)
    local cfg = _G.U5ESPConfig
    local myTeamId = character.TeamID or 0
    local allPawns = Game:GetAllPlayerPawns() or {}
    local enemies = {}
    local drawDist = cfg.INFO_DISTANCE * 100
    for _, tPawn in pairs(allPawns) do
        if #enemies >= 30 then break end
        if Valid(tPawn) and tPawn ~= character then
            if (tPawn.TeamID or 0) ~= myTeamId and not IsDeadBox(tPawn)
                and IsAlive(tPawn) and not IsDowned(tPawn) then
                if GetDistance(character, tPawn) <= drawDist
                    and (cfg.INFO_SHOW_BOT == 1 or not IsAI(tPawn)) then
                    table.insert(enemies, tPawn)
                end
            end
        end
    end
    return enemies
end
local function InfoESP()
    local cfg = _G.U5ESPConfig
    if cfg.INFO_ESP ~= 1 then return end
    local character = GameplayData.GetPlayerCharacter()
    if not Valid(character) then return end
    local hud = GetHUD()
    if not Valid(hud) then return end
    local now = os.clock()
    if now - infoLastRefresh > 2.0 then
        infoLastRefresh = now
        infoCachedEnemies = GetValidEnemiesInfo(character)
    end
    if #infoCachedEnemies == 0 then return end
    local color = { R=Clamp(cfg.INFO_R,0,255), G=Clamp(cfg.INFO_G,0,255),
                    B=Clamp(cfg.INFO_B,0,255), A=Clamp(cfg.INFO_A,0,255) }
    local offset = {X=cfg.INFO_X, Y=cfg.INFO_Y, Z=cfg.INFO_Z}
    local maxDisplay = math.min(#infoCachedEnemies, 25)
    for i = 1, maxDisplay do
        local tPawn = infoCachedEnemies[i]
        if Valid(tPawn) then
            hud:AddDebugText(GetWeaponName(tPawn), tPawn, 1.6, offset, offset,
                color, true, false, true, nil, cfg.INFO_FONT_SIZE, true)
        end
    end
end

local distCachedEnemies, distLastRefresh = {}, 0
local function GetValidEnemiesDist(character)
    local cfg = _G.U5ESPConfig
    local myTeamId = character.TeamID or 0
    local allPawns = Game:GetAllPlayerPawns() or {}
    local enemies = {}
    local drawDist = cfg.DIST_DISTANCE * 100
    for _, tPawn in pairs(allPawns) do
        if #enemies >= 30 then break end
        if Valid(tPawn) and tPawn ~= character then
            if (tPawn.TeamID or 0) ~= myTeamId and not IsDeadBox(tPawn)
                and IsAlive(tPawn) and not IsDowned(tPawn) then
                if GetDistance(character, tPawn) <= drawDist
                    and (cfg.DIST_SHOW_BOT == 1 or not IsAI(tPawn)) then
                    table.insert(enemies, tPawn)
                end
            end
        end
    end
    return enemies
end
local function DistESP()
    local cfg = _G.U5ESPConfig
    if cfg.DIST_ESP ~= 1 then return end
    local character = GameplayData.GetPlayerCharacter()
    if not Valid(character) then return end
    local hud = GetHUD()
    if not Valid(hud) then return end
    local now = os.clock()
    if now - distLastRefresh > 2.0 then
        distLastRefresh = now
        distCachedEnemies = GetValidEnemiesDist(character)
    end
    if #distCachedEnemies == 0 then return end
    local color = { R=Clamp(cfg.DIST_R,0,255), G=Clamp(cfg.DIST_G,0,255),
                    B=Clamp(cfg.DIST_B,0,255), A=Clamp(cfg.DIST_A,0,255) }
    local offset = {X=cfg.DIST_X, Y=cfg.DIST_Y, Z=cfg.DIST_Z}
    local maxDisplay = math.min(#distCachedEnemies, 25)
    for i = 1, maxDisplay do
        local tPawn = distCachedEnemies[i]
        if Valid(tPawn) then
            local dist = GetDistance(character, tPawn)
            local distM = math.floor(dist / 100 + 0.5)
            hud:AddDebugText(distM .. "m", tPawn, 1.6, offset, offset, color,
                true, false, true, nil, cfg.DIST_FONT_SIZE, true)
        end
    end
end

local lootBoxCache, lootBoxCacheTime = {}, 0
local function GetLootBoxes(myPos)
    local cfg = _G.U5ESPConfig
    if cfg.BOX_ESP ~= 1 then return {} end
    local maxDist = cfg.BOX_DISTANCE * 100
    local maxCount = cfg.BOX_COUNT or 10
    if maxCount <= 0 then maxCount = 999 end
    local currentTime = os.clock()
    if currentTime - lootBoxCacheTime > 3.0 then
        lootBoxCache = {}
        lootBoxCacheTime = currentTime
        local PlayerTombBox = import("PlayerTombBox")
        if not PlayerTombBox then return {} end
        local world = slua_GameFrontendHUD:GetWorld()
        if not Valid(world) then return {} end
        local GameplayStatics = import("GameplayStatics")
        if not GameplayStatics then return {} end
        local allBoxes = GameplayStatics.GetAllActorsOfClass(world, PlayerTombBox, nil)
        if not allBoxes then return {} end
        local boxList = {}
        local maxCheck = math.min(allBoxes:Num(), 100)
        for i = 0, maxCheck - 1 do
            local box = allBoxes:Get(i)
            if Valid(box) then
                local bPos = box:K2_GetActorLocation()
                if bPos then
                    local dx = bPos.X - myPos.X
                    local dy = bPos.Y - myPos.Y
                    local dz = bPos.Z - myPos.Z
                    local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
                    if dist <= maxDist then
                        table.insert(boxList, {box = box, pos = bPos, dist = dist})
                    end
                end
            end
        end
        if #boxList > 1 then
            table.sort(boxList, function(a, b) return a.dist < b.dist end)
        end
        if #boxList > maxCount then
            for i = maxCount + 1, #boxList do boxList[i] = nil end
        end
        lootBoxCache = boxList
    end
    return lootBoxCache
end
local function BoxESP()
    local cfg = _G.U5ESPConfig
    if cfg.BOX_ESP ~= 1 then return end
    local character = GameplayData.GetPlayerCharacter()
    if not Valid(character) then return end
    local hud = GetHUD()
    if not Valid(hud) then return end
    local myPos = character:K2_GetActorLocation()
    if not myPos then return end
    local boxList = GetLootBoxes(myPos)
    if #boxList == 0 then return end
    local color = { R=Clamp(cfg.BOX_R,0,255), G=Clamp(cfg.BOX_G,0,255),
                    B=Clamp(cfg.BOX_B,0,255), A=Clamp(cfg.BOX_A,0,255) }
    local offset = {X=cfg.BOX_X, Y=cfg.BOX_Y, Z=cfg.BOX_Z}
    local maxDisplay = math.min(#boxList, 20)
    for i = 1, maxDisplay do
        local data = boxList[i]
        if data and Valid(data.box) then
            local distM = math.floor(data.dist / 100)
            hud:AddDebugText("盒  " .. distM .. "m", data.box, 1.6, offset, offset,
                color, true, false, true, nil, cfg.BOX_FONT_SIZE, true)
        end
    end
end

local nativeActiveMarks, nativeLastEnemySet = {}, {}
local function NativeClearAllMarks()
    for _, mark in pairs(nativeActiveMarks) do
        if mark then
            pcall(function()
                if InGameMarkTools.ClientRemoveMapMark then
                    InGameMarkTools.ClientRemoveMapMark(mark)
                elseif InGameMarkTools.HideMapMark then
                    InGameMarkTools.HideMapMark(mark)
                end
            end)
        end
    end
    nativeActiveMarks = {}
end
local function GetValidEnemiesNative(character)
    local cfg = _G.U5ESPConfig
    local myTeamId = character.TeamID or 0
    local allPawns = Game:GetAllPlayerPawns() or {}
    local enemies, enemySet = {}, {}
    local drawDist = cfg.NATIVE_DISTANCE * 100
    for _, enemy in pairs(allPawns) do
        if Valid(enemy) and enemy ~= character then
            if (enemy.TeamID or 0) ~= myTeamId and not IsDeadBox(enemy)
                and not IsDowned(enemy) and IsAlive(enemy) then
                if GetDistance(character, enemy) <= drawDist
                    and (cfg.NATIVE_SHOW_BOT == 1 or not IsAI(enemy)) then
                    table.insert(enemies, enemy)
                    enemySet[tostring(enemy)] = true
                end
            end
        end
    end
    return enemies, enemySet
end
local function InitNativeESPConfig()
    pcall(function()
        local screenMarkConfig = GamePlayTools.GetCurrentConfig("ScreenMarkConfig")
        if not screenMarkConfig then return end
        if not screenMarkConfig[9999] then
            screenMarkConfig[9999] = {
                UIPathName = "/Game/Mod/EvoBase/BluePrints/UIBP/QuickSign/QuickSign_TipHitEnemy_UIBP_New.QuickSign_TipHitEnemy_UIBP_New_C",
                MaxWidgetNum = 99, MaxShowDistance = 6000000,
                bBindOutScreen = true, bBindBlocked = true, bIsBindingActor = true,
                BindSocketName = "head", bUseLuaWorldSocketName = true,
                WorldPositionOffset = FVector(0, 0, 70),
                bNeedPreLoad = true, Priority = 2
            }
            if InGameMarkTools.ScreenMarkManager and
               InGameMarkTools.ScreenMarkManager.OnInitMarkGroupData then
                InGameMarkTools.ScreenMarkManager:OnInitMarkGroupData(9999)
            end
        end
        if screenMarkConfig[1006] then
            screenMarkConfig[1006].bBindBlocked = true
            screenMarkConfig[1006].bBindOutScreen = true
            screenMarkConfig[1006].MaxWidgetNum = 99
            screenMarkConfig[1006].MaxShowDistance = 6000000
            screenMarkConfig[1006].bScaleByDistance = false
        end
    end)
end
local function NativeESP()
    local cfg = _G.U5ESPConfig
    if cfg.NATIVE_ESP ~= 1 then
        if #nativeActiveMarks > 0 then NativeClearAllMarks() end
        nativeLastEnemySet = {}
        return
    end
    local character = GameplayData.GetPlayerCharacter()
    if not Valid(character) then return end
    if cfg.NATIVE_HP_BAR == 1 then
        local enemies, enemySet = GetValidEnemiesNative(character)
        local needRefresh = false
        for id, _ in pairs(enemySet) do
            if not nativeLastEnemySet[id] then needRefresh = true break end
        end
        if not needRefresh then
            for id, _ in pairs(nativeLastEnemySet) do
                if not enemySet[id] then needRefresh = true break end
            end
        end
        if needRefresh then
            NativeClearAllMarks()
            local index = 1
            for _, enemy in ipairs(enemies) do
                local enemyPos = enemy:K2_GetActorLocation()
                local mark = InGameMarkTools.ClientAddMapMark(1006, enemyPos, 0, "", 4, enemy)
                if mark then nativeActiveMarks[index] = mark index = index + 1 end
            end
        end
        nativeLastEnemySet = enemySet
    else
        if #nativeActiveMarks > 0 then NativeClearAllMarks() end
        nativeLastEnemySet = {}
    end
    local allPawns = Game:GetAllPlayerPawns() or {}
    local validEnemies, validEnemySet = GetValidEnemiesNative(character)
    for _, enemy in pairs(allPawns) do
        if Valid(enemy) and enemy ~= character then
            local shouldShow = (cfg.NATIVE_FRAME == 1 and validEnemySet[tostring(enemy)])
            pcall(function()
                if enemy.Replay_SetVisiableOfFrameUI then
                    enemy:Replay_SetVisiableOfFrameUI(shouldShow or false)
                end
            end)
        end
    end
    if cfg.NATIVE_FRAME == 1 then
        for _, enemy in ipairs(validEnemies) do
            pcall(function()
                if enemy.Replay_IsEnemyFrameUIExisted then
                    if not enemy:Replay_IsEnemyFrameUIExisted() then
                        enemy:Replay_CreateEnemyFrameUI(true, true)
                    end
                    if enemy.Replay_SetVisiableOfFrameUI then
                        enemy:Replay_SetVisiableOfFrameUI(true)
                    end
                end
            end)
        end
    end
end

-- ============================================================
-- 范围
-- ============================================================
local function ApplyHitboxScale()
    local cfg = _G.U5RangeConfig
    if cfg.ENABLED ~= 1 then return end
    local char = GameplayData.GetPlayerCharacter()
    if not Valid(char) then return end
    local allChars = Game:GetAllPlayerPawns() or {}
    for _, c in pairs(allChars) do
        if Valid(c) and c ~= char and c.TeamID ~= char.TeamID and IsPawnAlive2(c) then
            local mesh = c.Mesh
            if Valid(mesh) then
                local physAsset = mesh.PhysicsAssetOverride
                if not Valid(physAsset) and Valid(mesh.SkeletalMesh) then
                    physAsset = mesh.SkeletalMesh.PhysicsAsset
                end
                if Valid(physAsset) and physAsset.SkeletalBodySetups then
                    _G._MBones = _G._MBones or {}
                    local assetName = (physAsset.GetName and physAsset:GetName())
                        or tostring(physAsset)
                    if not _G._MBones[assetName] then
                        local setups = physAsset.SkeletalBodySetups
                        for i = 1, 80 do
                            local bs = nil
                            pcall(function()
                                bs = (type(setups.Get)=="function") and setups:Get(i-1) or setups[i]
                            end)
                            if not bs or not Valid(bs) then break end
                            local bn = tostring(bs.BoneName):lower()
                            local pct = nil
                            if string.find(bn, "head") then pct = cfg.HEAD
                            elseif string.find(bn, "neck") then pct = cfg.NECK
                            elseif string.find(bn, "pelvis") then pct = cfg.PELVIS
                            elseif string.find(bn, "spine") then pct = cfg.SPINE
                            elseif string.find(bn, "upperarm") then pct = cfg.UPPERARM
                            elseif string.find(bn, "lowerarm") then pct = cfg.LOWERARM
                            elseif string.find(bn, "hand") then pct = cfg.HAND
                            elseif string.find(bn, "thigh") then pct = cfg.THIGH
                            elseif string.find(bn, "calf") then pct = cfg.CALF
                            elseif string.find(bn, "foot") then pct = cfg.FOOT
                            end
                            if pct and pct > 0 then
                                local sc = 1.0 + pct / 100.0
                                local ag = bs.AggGeom
                                pcall(function()
                                    local bx = (ag and ag.BoxElems) or bs.BoxElems
                                    if bx then
                                        local b = (type(bx.Get)=="function") and bx:Get(0) or bx[1]
                                        if b then
                                            b.X = (b.X or 30) * sc
                                            b.Y = (b.Y or 30) * sc
                                            b.Z = (b.Z or 60) * sc
                                            if type(bx.Set)=="function" then bx:Set(0,b) else bx[1] = b end
                                            if ag then bs.AggGeom = ag else bs.BoxElems = bx end
                                        end
                                    end
                                end)
                                pcall(function()
                                    local sp = (ag and ag.SphylElems) or bs.SphylElems
                                    if sp then
                                        local s = (type(sp.Get)=="function") and sp:Get(0) or sp[1]
                                        if s then
                                            if s.Radius then s.Radius = s.Radius * sc end
                                            if s.Length then s.Length = s.Length * sc end
                                            if type(sp.Set)=="function" then sp:Set(0,s) else sp[1] = s end
                                            if ag then bs.AggGeom = ag else bs.SphylElems = sp end
                                        end
                                    end
                                end)
                                pcall(function()
                                    local sr = (ag and ag.SphereElems) or bs.SphereElems
                                    if sr then
                                        local r = (type(sr.Get)=="function") and sr:Get(0) or sr[1]
                                        if r and r.Radius then
                                            r.Radius = r.Radius * sc
                                            if type(sr.Set)=="function" then sr:Set(0,r) else sr[1] = r end
                                            if ag then bs.AggGeom = ag else bs.SphereElems = sr end
                                        end
                                    end
                                end)
                            end
                        end
                        _G._MBones[assetName] = true
                        if mesh.RecreatePhysicsState then mesh:RecreatePhysicsState() end
                    end
                end
            end
        end
    end
end

-- ============================================================
-- 枪械
-- ============================================================
local function ApplyWeaponMods(weaponEntity)
    if not Valid(weaponEntity) then return end
    local cfg = _G.GunFuncConfig
    if cfg.NO_RECOIL_ADS == 1 then weaponEntity.RecoilKickADS = 0.0 end
    if cfg.ANTI_SHAKE == 1 then weaponEntity.AnimationKick = 0.0 end
    if cfg.EXTRA_HIT_SCALE > 0 then
        weaponEntity.ExtraHitPerformScale = cfg.EXTRA_HIT_SCALE
    end
    if cfg.SUPER_FIRE_RATE == 1 then
        weaponEntity.ShootInterval = cfg.FIRE_RATE_VALUE
    end
    if cfg.ALL_GUN_FOCUS == 1 then
        weaponEntity.GameDeviationAccuracy = cfg.FOCUS_VALUE
        weaponEntity.GameDeviationFactor = cfg.FOCUS_VALUE
        weaponEntity.ShotGunHorizontalSpread = cfg.FOCUS_VALUE
        weaponEntity.ShotGunVerticalSpread = cfg.FOCUS_VALUE
        weaponEntity.CrossHairBurstSpeed = cfg.FOCUS_VALUE
        weaponEntity.CrossHairBurstIncreaseSpeed = cfg.FOCUS_VALUE
    end
    if cfg.QUICK_SCOPE == 1 then weaponEntity.WeaponAimInTime = cfg.SCOPE_VALUE end
    if cfg.QUICK_SWITCH == 1 then
        weaponEntity.SwitchFromBackpackToIdleTime = cfg.SWITCH_VALUE
        weaponEntity.SwitchFromIdleToBackpackTime = cfg.SWITCH_VALUE
    end
end

local lastWeaponEntity, lastConfigHash = nil, 0
local function GetConfigHash()
    local cfg = _G.GunFuncConfig
    return cfg.NO_RECOIL_ADS.."|"..cfg.ANTI_SHAKE.."|"..cfg.SUPER_FIRE_RATE.."|"..
           cfg.FIRE_RATE_VALUE.."|"..cfg.ALL_GUN_FOCUS.."|"..cfg.FOCUS_VALUE.."|"..
           cfg.QUICK_SCOPE.."|"..cfg.SCOPE_VALUE.."|"..cfg.QUICK_SWITCH.."|"..
           cfg.SWITCH_VALUE.."|"..cfg.EXTRA_HIT_SCALE
end
local function GunMainTick()
    local uCon = slua_GameFrontendHUD:GetPlayerController()
    if not Valid(uCon) then return end
    local currentPawn = uCon:GetCurPawn()
    if not Valid(currentPawn) then return end
    local wm = currentPawn.WeaponManagerComponent
    if not wm then return end
    local weapon = wm.CurrentWeaponReplicated
    if not weapon then return end
    local entity = weapon.ShootWeaponEntityComp
    if not Valid(entity) then return end
    local currentHash = GetConfigHash()
    if currentHash ~= lastConfigHash or entity ~= lastWeaponEntity then
        lastConfigHash, lastWeaponEntity = currentHash, entity
        ApplyWeaponMods(entity)
    end
end

-- ============================================================
-- 基本
-- ============================================================
local lastApplyFOV = 0
local function GetLocalPlayerLP()
    local ok, UIUtil = pcall(require, "client.common.ui_util")
    if not ok or not UIUtil or not UIUtil.GetGameInstance then return nil end
    local WorldContextObject = UIUtil.GetGameInstance()
    if not WorldContextObject then return nil end
    local ok_g, UGameplayStatics = pcall(import, "GameplayStatics")
    if not ok_g or not UGameplayStatics then return nil end
    local PlayerController = UGameplayStatics.GetPlayerController(WorldContextObject, 0)
    if not PlayerController then return nil end
    local LP = PlayerController.Player
    if not LP or not Valid(LP) then return nil end
    return LP
end
local function ApplyMemoryFOV(cfg)
    if cfg.MEMORY_FOV ~= 1 then return end
    local fov = cfg.MEMORY_FOV_VALUE
    if fov <= 0 then return end
    local LP = GetLocalPlayerLP()
    if not LP then return end
    LP.AspectRatioAxisConstraint = 0
    pcall(function()
        local uCon = slua_GameFrontendHUD:GetPlayerController()
        if not Valid(uCon) then return end
        local currentPawn = uCon:GetCurPawn()
        if not Valid(currentPawn) then return end
        local tpCam = currentPawn.ThirdPersonCameraComponent
        if Valid(tpCam) then tpCam.FieldOfView = fov end
    end)
end
local function ApplyFOV(cfg)
    local now = os.clock()
    if now - lastApplyFOV < 0.5 then return end
    lastApplyFOV = now
    pcall(function()
        local uCon = slua_GameFrontendHUD:GetPlayerController()
        if not (Valid(uCon) and Game:IsClassOf(uCon, ASTExtraPlayerController)) then return end
        local currentPawn = uCon:GetCurPawn()
        if not Valid(currentPawn) then return end
        if cfg.WIDE_ANGLE == 1 then
            if currentPawn.ThirdPersonCameraComponent and cfg.TP_FOV > 0 then
                local tpCam = currentPawn.ThirdPersonCameraComponent
                if tpCam.FieldOfView ~= cfg.TP_FOV then tpCam.FieldOfView = cfg.TP_FOV end
            end
            if cfg.SCOPE_FOV > 0 then
                local scopingArm = currentPawn.ScopingSpringArm
                if Valid(scopingArm) and scopingArm.TargetArmLength ~= cfg.SCOPE_FOV then
                    scopingArm.TargetArmLength = cfg.SCOPE_FOV
                end
            end
        end
        ApplyMemoryFOV(cfg)
    end)
end

local cachedGI = nil
local function GetGameInstance()
    if cachedGI and Valid(cachedGI) then return cachedGI end
    if slua_GameFrontendHUD then
        local gi = slua_GameFrontendHUD:GetGameInstance()
        if Valid(gi) then cachedGI = gi return gi end
    end
    return nil
end

local unlocked, lastFPSValue = false, 0
local function UnlockAllGraphics(cfg)
    if unlocked then return end
    pcall(function()
        local graphics = require("client.slua.logic.setting.logic_setting_graphics")
        local fpsComp = require("client.slua.umg.NewSetting.GraphicsNew.Comps.GSC_FPS")
        local fpsFT = require("client.slua.umg.NewSetting.GraphicsNew.Comps.GSC_FPSFT")
        local db = require("client.slua.umg.NewSetting.GraphicsNew.GraphicSettingDB")
        if graphics and graphics.SetFPS then
            local origSetFPS = graphics.SetFPS
            graphics.SetFPS = function(self, lvl)
                if origSetFPS then origSetFPS(self, lvl) end
                if lvl == 8 then
                    local fps = cfg.LOCK_FPS > 0 and cfg.LOCK_FPS or 999
                    self:ExecuteCMD("t.MaxFPS", tostring(fps))
                    self:ExecuteCMD("r.FrameRateLimit", tostring(fps))
                end
            end
        end
        if fpsComp and fpsComp.__inner_impl then
            local impl = fpsComp.__inner_impl
            impl.GetMaxFPSLevel = function() return 8, 8 end
            impl.InitRealSupportFPS = function(self)
                local t = {}
                for i = 1, 8 do t[i] = {true, true} end
                if db then db:UpdateUIData(db.RealSupportFPS, t, false) end
                return t
            end
            impl.UpdateSelectedFPSState = function(self, lvl)
                local fpsMap = {[2]=20,[3]=25,[4]=30,[5]=40,[6]=60,[7]=90,[8]=120}
                for i = 2, 8 do
                    local nodeName = "NodeFps" .. (fpsMap[i] or 120)
                    local node = self.UIRoot[nodeName]
                    if Valid(node) then
                        node:SetIsEnabled(true)
                        pcall(function() node:SetRenderOpacity(1.0) end)
                        local sw = self.UIRoot["WidgetSwitcher_" .. i]
                        if Valid(sw) then sw:SetActiveWidgetIndex(i == lvl and 0 or 1) end
                    end
                end
            end
        end
        if fpsFT and fpsFT.__inner_impl then
            local impl = fpsFT.__inner_impl
            local MIN_FPS, STEP = 90, 5
            local clamp = function(v, lo, hi)
                if v < lo then return lo end
                if hi < v then return hi end
                return v
            end
            impl.ShowOrHide = function(self)
                self:SelfHitTestInvisible()
                if self.InitFPSFTSwitch then self:InitFPSFTSwitch() end
            end
            impl.InitFPSFTSwitch = function(self)
                local on = db:GetUIData(db.FPSFineTuneSwitch)
                if self.UIRoot.Setting_Switch then
                    self.UIRoot.Setting_Switch:SetSwitcherEnable2(on, true)
                end
                if self.UIRoot.CanvasPanel_8 then
                    self:SetWidgetVisible(self.UIRoot.CanvasPanel_8, on)
                end
                if self.UIRoot.WidgetSwitcher_0 then
                    self.UIRoot.WidgetSwitcher_0:SetActiveWidgetIndex(2)
                end
                if self.InitFPSFTValueCustom then self:InitFPSFTValueCustom() end
            end
            impl.InitFPSFTValueCustom = function(self)
                local r = self.UIRoot
                local on = db:GetUIData(db.FPSFineTuneSwitch)
                local maxFPS = cfg.LOCK_FPS > 0 and cfg.LOCK_FPS or 999
                local val = on and (db:GetUIData(db.FPSFineTuneNum) or maxFPS) or maxFPS
                if on then
                    r.Slider_screen3:SetLocked(false)
                    r.ProgressBar_screen3:SetFillColorAndOpacity(FLinearColor(1,1,1,1))
                    r.Slider_screen3:SetSliderHandleColor(FLinearColor(1,1,1,1))
                else
                    r.Slider_screen3:SetLocked(true)
                    r.ProgressBar_screen3:SetFillColorAndOpacity(FLinearColor(1,0.625,0.6,1))
                    r.Slider_screen3:SetSliderHandleColor(FLinearColor(1,0.625,0.6,1))
                end
                local norm = (val - MIN_FPS) / (maxFPS - MIN_FPS)
                r.Veihclescreen3:SetText(tostring(val))
                r.Slider_screen3:SetValue(norm)
                r.ProgressBar_screen3:SetPercent(norm)
            end
            impl.OnFPSFTValueChange3 = function(self, val)
                db:UpdateUIData(db.FPSFineTuneNum, val)
                if self.InitFPSFTValueCustom then self:InitFPSFTValueCustom() end
                if self:GetParentUI() then self:GetParentUI():SetDirty(true) end
                local gi = GetGameInstance()
                if gi then
                    gi:ExecuteCMD("t.MaxFPS", tostring(val))
                    gi:ExecuteCMD("r.FrameRateLimit", tostring(val))
                end
            end
            impl.OnFPSFTSliderValueChange3 = function(self, nv)
                if not db:GetUIData(db.FPSFineTuneSwitch) then return end
                local maxFPS = cfg.LOCK_FPS > 0 and cfg.LOCK_FPS or 999
                local raw = math.floor((MIN_FPS + nv * (maxFPS - MIN_FPS)) / STEP + 0.5) * STEP
                self:OnFPSFTValueChange3(clamp(raw, MIN_FPS, maxFPS))
            end
            impl.OnFPSFTAdd3 = function(self)
                local maxFPS = cfg.LOCK_FPS > 0 and cfg.LOCK_FPS or 999
                local cur = db:GetUIData(db.FPSFineTuneNum) or 90
                self:OnFPSFTValueChange3(math.min(maxFPS, cur + STEP))
            end
            impl.OnFPSFTMinus3 = function(self)
                local maxFPS = cfg.LOCK_FPS > 0 and cfg.LOCK_FPS or 999
                local cur = db:GetUIData(db.FPSFineTuneNum) or 90
                self:OnFPSFTValueChange3(math.max(MIN_FPS, cur - STEP))
            end
            impl.OnFPSFTAdd = impl.OnFPSFTAdd3
            impl.OnFPSFTMinus = impl.OnFPSFTMinus3
            impl.OnFPSFTSliderValueChange = impl.OnFPSFTSliderValueChange3
        end
        unlocked = true
    end)
end
local function LockFPS(cfg)
    local targetFPS = cfg.LOCK_FPS > 0 and cfg.LOCK_FPS or 999
    if targetFPS == lastFPSValue then return end
    lastFPSValue = targetFPS
    local gi = GetGameInstance()
    if gi then
        pcall(function()
            gi:ExecuteCMD("t.MaxFPS", tostring(targetFPS))
            gi:ExecuteCMD("r.FrameRateLimit", tostring(targetFPS))
        end)
    end
end
local optApplied = false
local function ApplyPerformanceOptimization(cfg)
    if optApplied then return end
    if cfg.PERFORMANCE_OPT ~= 1 then return end
    local gi = GetGameInstance()
    if not gi then return end
    pcall(function()
        gi:ExecuteCMD("r.Streaming.DropMips", "3")
        gi:ExecuteCMD("r.Streaming.Boost", "1")
        gi:ExecuteCMD("r.Streaming.LimitPoolSizeToVRAM", "1")
        gi:ExecuteCMD("r.Streaming.FramesForFullUpdate", "10")
        gi:ExecuteCMD("r.Streaming.MaxNumTexturesToStreamPerFrame", "4")
        gi:ExecuteCMD("p.PhysicsAsyncScene", "1")
        gi:ExecuteCMD("p.PhysicsBodiesPerScene", "500")
        gi:ExecuteCMD("a.AnimUpdateRate", "2")
        gi:ExecuteCMD("a.EnableParallelAnimEvaluation", "1")
        gi:ExecuteCMD("net.MaxConnections", "32")
        gi:ExecuteCMD("Slate.EnableUIRefresh", "1")
        gi:ExecuteCMD("r.VSync", "0")
        if Client.GetMemorySize and Client.GetMemorySize() <= 4 then
            gi:ExecuteCMD("diy.EnableDecalBakingRTCache", "0")
            gi:ExecuteCMD("r.Fog", "0")
            gi:ExecuteCMD("r.Atmosphere", "0")
        end
        optApplied = true
    end)
end

-- ============================================================
-- 自瞄
-- ============================================================
local function AimGetTargetVelocity(target)
    local vel = nil
    pcall(function()
        if type(target.GetVelocity) == "function" then
            vel = target:GetVelocity()
        elseif target.CharacterMovement then
            vel = target.CharacterMovement.Velocity
        end
    end)
    return vel
end
local function GetPredictedPosition(currentPos, velocity, predictionTimeSeconds, maxPredictionDistance)
    if not currentPos or not velocity then return currentPos end
    local speed = math.sqrt(velocity.X*velocity.X + velocity.Y*velocity.Y + velocity.Z*velocity.Z)
    if speed < 50 then return currentPos end
    local maxTime = maxPredictionDistance / speed
    local deltaTime = math.min(predictionTimeSeconds, maxTime)
    return {
        X = currentPos.X + velocity.X * deltaTime,
        Y = currentPos.Y + velocity.Y * deltaTime,
        Z = currentPos.Z + velocity.Z * deltaTime,
    }
end

_G.AimVelocityCache = _G.AimVelocityCache or {}
local function GetSmoothedVelocity(target, rawVel, alpha)
    if not rawVel then return nil end
    local key = tostring(target)
    local cache = _G.AimVelocityCache
    local nowT = os.clock()
    local prev = cache[key]
    if prev and (nowT - prev.t) < 0.5 then
        local a = alpha or 0.4
        local b = 1 - a
        local v = {
            X = rawVel.X * a + prev.X * b,
            Y = rawVel.Y * a + prev.Y * b,
            Z = rawVel.Z * a + prev.Z * b,
            t = nowT,
        }
        cache[key] = v
        return v
    end
    local v = { X = rawVel.X, Y = rawVel.Y, Z = rawVel.Z, t = nowT }
    cache[key] = v
    local n = 0
    for _ in pairs(cache) do n = n + 1 end
    if n > 128 then _G.AimVelocityCache = {} end
    return v
end

local BULLET_SPEED_TABLE = {
    ["AWM"]=907,["M24"]=790,["Kar98k"]=760,["Mosin"]=760,["Win94"]=760,
    ["SLR"]=840,["SKS"]=800,["Mini14"]=990,["QBU"]=853,["Mk14"]=853,["VSS"]=300,
    ["M416"]=880,["SCAR"]=870,["AKM"]=715,["M762"]=715,["Groza"]=715,
    ["QBZ"]=780,["G36C"]=790,["M16A4"]=900,["MK47"]=780,["FAMAS"]=940,["AUG"]=940,
    ["UZI"]=350,["Vector"]=300,["UMP"]=400,["MP5K"]=400,["PP19"]=400,["P90"]=970,
    ["DP-28"]=783,["M249"]=915,
}
local function GetBulletSpeed(weapon)
    local default = 800
    pcall(function()
        local v = tonumber(_G.AimBotConfig.BULLET_SPEED)
        if v and v > 0 then default = v end
    end)
    if not weapon or not Valid(weapon) then return default end
    local wName = ""
    pcall(function()
        if type(weapon.GetWeaponName) == "function" then
            wName = weapon:GetWeaponName() or ""
        end
    end)
    for k, v in pairs(BULLET_SPEED_TABLE) do
        if wName:find(k, 1, true) then return v end
    end
    return default
end

local cachedEnemies, lastEnemyRefresh = {}, 0
_G.AimBotCurrentTarget = nil
local originalRecoilKickADS = nil
local originalRecoilKickADS_restored = false
local lastADSState = false
local lastAimTime = 0
local fireCount = 0
local lastFireTick = 0
_G.AimLockTarget = nil
local _EParachuteState, _EPawnState = nil, nil

local function HasValidWeapon(player)
    if not Valid(player) then return false end
    local weapon = player.WeaponManagerComponent and
        player.WeaponManagerComponent.CurrentWeaponReplicated
    if not weapon and type(player.GetCurrentShootWeapon) == "function" then
        weapon = player:GetCurrentShootWeapon()
    end
    if Valid(weapon) then
        local wID = type(weapon.GetWeaponID) == "function" and weapon:GetWeaponID() or 0
        if wID > 0 then return true end
    end
    return false
end

_G.GetEnemyTargetsFromActors = function(radius)
    local result = {}
    local player = GameplayData.GetPlayerCharacter()
    if not Valid(player) then return result end
    local allCharacters = {}
    if GameplayData.GetAllPlayerCharacters then
        allCharacters = GameplayData.GetAllPlayerCharacters()
    elseif GameplayData.GameCharacters then
        for _, char in pairs(GameplayData.GameCharacters) do
            table.insert(allCharacters, char)
        end
    end
    local myTeam = player:GetTeamID()
    for _, actor in pairs(allCharacters) do
        if Valid(actor) and actor ~= player and actor.GetTeamID and actor:IsAlive() then
            if actor:GetTeamID() ~= myTeam then
                local dist = player:GetDistanceTo(actor)
                if dist <= radius then
                    table.insert(result, actor)
                end
            end
        end
    end
    return result
end

local function AimIsBot(pawn)
    if not Valid(pawn) then return false end
    if pawn.bIsAI == true or pawn.IsAI == true then return true end
    local teamId = pawn.TeamID or 0
    if teamId > 100 then return true end
    local pState = pawn.PlayerState
    if Valid(pState) and (pState.bIsABot or pState.bIsBot) then return true end
    return false
end
local function IsKnocked(pawn)
    if not Valid(pawn) then return false end
    if pawn.HealthStatus == 1 then return true end
    if pawn.IsNearDeath then return pawn:IsNearDeath() end
    if pawn.Health and pawn.Health <= 0 then return true end
    return false
end
local function IsEnemyVisible(pc, target)
    local cfg = _G.AimBotConfig
    if cfg.WALL_CHECK == 0 then return true end
    if not Valid(pc) or not Valid(target) then return false end
    local bVisible = false
    pcall(function() bVisible = pc:LineOfSightTo(target) end)
    return bVisible
end
local function GetBoneNameByIndex(idx)
    if idx == 0 then return "head"
    elseif idx == 1 then return "spine_03"
    elseif idx == 2 then return "pelvis"
    end
    return "head"
end
local function GetTargetBonePos(target, boneName)
    local pos = nil
    pcall(function()
        if type(target.GetBoneLocation) == "function" then
            pos = target:GetBoneLocation(boneName)
        elseif type(target.GetSocketLocation) == "function" then
            pos = target:GetSocketLocation(boneName)
        elseif type(target.GetBonePos) == "function" then
            pos = target:GetBonePos(boneName, {X=0, Y=0, Z=0})
        end
    end)
    return pos
end
local function GetFallbackBonePos(target, boneIdx)
    local pos = nil
    pcall(function()
        local fallbackBones = {"neck_01", "spine_03", "spine_02", "pelvis"}
        for _, bone in ipairs(fallbackBones) do
            pos = GetTargetBonePos(target, bone)
            if pos and pos.X ~= 0 and pos.Y ~= 0 and pos.Z ~= 0 then
                if boneIdx == 0 then
                    pos.Z = pos.Z + 30
                elseif boneIdx == 1 then
                    pos.Z = pos.Z + 5
                end
                break
            end
        end
    end)
    return pos
end

local function SaveOriginalRecoilKickADS(weapon)
    if originalRecoilKickADS_restored then return end
    local entity = weapon.ShootWeaponEntity_GEN_VARIABLE
    if Valid(entity) and originalRecoilKickADS == nil then
        originalRecoilKickADS = entity.RecoilKickADS
        originalRecoilKickADS_restored = true
        return
    end
    entity = weapon.ShootWeaponEntity
    if Valid(entity) and originalRecoilKickADS == nil then
        originalRecoilKickADS = entity.RecoilKickADS
        originalRecoilKickADS_restored = true
        return
    end
    if Valid(weapon.ShootWeaponComponent) then
        entity = weapon.ShootWeaponComponent.ShootWeaponEntityComponent
        if Valid(entity) and originalRecoilKickADS == nil then
            originalRecoilKickADS = entity.RecoilKickADS
            originalRecoilKickADS_restored = true
        end
    end
end
local function SetRecoilKickADS(weapon, value)
    pcall(function()
        if not Valid(weapon) then return end
        local entity = weapon.ShootWeaponEntity_GEN_VARIABLE
        if Valid(entity) then entity.RecoilKickADS = value end
        entity = weapon.ShootWeaponEntity
        if Valid(entity) then entity.RecoilKickADS = value end
        if Valid(weapon.ShootWeaponComponent) then
            entity = weapon.ShootWeaponComponent.ShootWeaponEntityComponent
            if Valid(entity) then entity.RecoilKickADS = value end
        end
    end)
end
local function HandleRecoilKickADS()
    pcall(function()
        local player = GameplayData.GetPlayerCharacter()
        if not Valid(player) then return end
        if player.bFreeView == true or player.bCableCarView == true then return end
        local weapon = player.WeaponManagerComponent and
            player.WeaponManagerComponent.CurrentWeaponReplicated
        if not weapon and type(player.GetCurrentShootWeapon) == "function" then
            weapon = player:GetCurrentShootWeapon()
        end
        if not Valid(weapon) then return end
        local cfg = _G.AimBotConfig
        if cfg.ENABLED ~= 1 then
            if originalRecoilKickADS ~= nil then
                SetRecoilKickADS(weapon, originalRecoilKickADS)
            end
            return
        end
        SaveOriginalRecoilKickADS(weapon)
        local isADS = player.bIsGunADS
        if isADS ~= lastADSState then
            lastADSState = isADS
            local value = isADS and 0 or originalRecoilKickADS
            SetRecoilKickADS(weapon, value)
        end
    end)
end

_G.AimTouch = function()
    pcall(function()
        local now = os.clock()
        _G.AIMTOUCH_LAST_TICK = now
        if now - lastAimTime < 0.01 then return end
        lastAimTime = now

        local cfg = _G.AimBotConfig
        HandleRecoilKickADS()
        if cfg.ENABLED ~= 1 then return end

        local player = GameplayData.GetPlayerCharacter()
        if not Valid(player) then return end
        local pc = player:GetPlayerControllerSafety()
        if not Valid(pc) then return end

        if player.bFreeView == true or player.bCableCarView == true then return end
        if player.bUseControllerRotationYaw == false then return end

        if not _EParachuteState then _EParachuteState = import("EParachuteState") end
        if player.ParachuteState and player.ParachuteState ~= _EParachuteState.PS_None then return end

        if type(player.IsAlive) == "function" and not player:IsAlive() then return end
        if not _EPawnState then _EPawnState = import("EPawnState") end
        if type(player.HasState) == "function" then
            if player:HasState(_EPawnState.Dying) or player:HasState(_EPawnState.Dead) then return end
        end

        local isFiring = player.bIsWeaponFiring
        local isADS = player.bIsGunADS

        if not isFiring and not isADS and cfg.HIP_AIM ~= 1 then return end
        if cfg.HIP_AIM ~= 1 and cfg.FIRE_AIM ~= 1 and
           cfg.SCOPE_FIRE_AIM ~= 1 and cfg.SCOPE_AIM ~= 1 then return end

        local mode = 0
        local speedVal = 50
        local recoilVal = 0
        local boneIdx = 0
        local fovVal = 20
        local maxDistMeters = 30
        local noAimDist = 0

        if isADS and not isFiring and cfg.SCOPE_AIM == 1 then
            mode = 4
            speedVal = cfg.SCOPE_SPEED or 40
            recoilVal = 0
            boneIdx = cfg.SCOPE_BONE or 1
            fovVal = cfg.SCOPE_FOV or 8
            maxDistMeters = cfg.SCOPE_DIST or 200
            noAimDist = cfg.SCOPE_NO_AIM_DIST or 20
        elseif isADS and isFiring and cfg.SCOPE_FIRE_AIM == 1 then
            mode = 3
            speedVal = cfg.SCOPE_FIRE_SPEED or 40
            recoilVal = cfg.SCOPE_FIRE_RECOIL or 5
            boneIdx = cfg.SCOPE_FIRE_BONE or 1
            fovVal = cfg.SCOPE_FIRE_FOV or 8
            maxDistMeters = cfg.SCOPE_FIRE_DIST or 200
            noAimDist = cfg.SCOPE_FIRE_NO_AIM_DIST or 20
        elseif isFiring and cfg.FIRE_AIM == 1 then
            mode = 1
            speedVal = cfg.FIRE_SPEED or 50
            recoilVal = cfg.FIRE_RECOIL or 0
            boneIdx = cfg.FIRE_BONE or 0
            fovVal = cfg.FIRE_FOV or 20
            maxDistMeters = cfg.FIRE_DIST or 30
        elseif cfg.HIP_AIM == 1 then
            if not HasValidWeapon(player) then return end
            mode = 0
            speedVal = cfg.HIP_SPEED or 50
            recoilVal = cfg.HIP_RECOIL or 0
            boneIdx = cfg.HIP_BONE or 0
            fovVal = cfg.HIP_FOV or 20
            maxDistMeters = cfg.HIP_DIST or 30
        else
            return
        end

        local weapon = player.WeaponManagerComponent and
            player.WeaponManagerComponent.CurrentWeaponReplicated
        if not weapon and type(player.GetCurrentShootWeapon) == "function" then
            weapon = player:GetCurrentShootWeapon()
        end

        if Valid(weapon) then
            local wID = type(weapon.GetWeaponID) == "function" and weapon:GetWeaponID() or 0
            local wName = type(weapon.GetWeaponName) == "function" and weapon:GetWeaponName() or ""
            if (wID >= 1030000 and wID < 1040000) or wName:find("S686") or
               wName:find("S1897") or wName:find("S12") or wName:find("DBS") or
               wName:find("M1014") then
                local currentAmmo = 1
                if type(weapon.GetCurrentAmmo) == "function" then
                    currentAmmo = weapon:GetCurrentAmmo()
                elseif weapon.CurrentAmmo ~= nil then
                    currentAmmo = weapon.CurrentAmmo
                end
                if currentAmmo <= 0 then return end
            end
        end

        local aimKnock = cfg.AIM_KNOCK == 1
        local aimBot = cfg.AIM_BOT == 1
        local currentMaxDist = maxDistMeters * 100
        local priority = cfg.AIM_PRIORITY or 0
        local noAimDistUnits = noAimDist * 100

        if now - lastEnemyRefresh > 0.2 then
            lastEnemyRefresh = now
            cachedEnemies = _G.GetEnemyTargetsFromActors(currentMaxDist)
        end
        local enemies = cachedEnemies
        if not enemies or #enemies == 0 then return end

        local KismetMathLibrary = import("KismetMathLibrary")
        local selBoneName = GetBoneNameByIndex(boneIdx)

        local bestTarget, bestPos, bestScore, bestDist = nil, nil, 99999999, 0

        local camLoc = nil
        pcall(function()
            if type(pc.GetCameraLocation) == "function" then
                camLoc = pc:GetCameraLocation()
            elseif pc.PlayerCameraManager and
                   type(pc.PlayerCameraManager.GetCameraLocation) == "function" then
                camLoc = pc.PlayerCameraManager:GetCameraLocation()
            end
        end)
        if not camLoc or (camLoc.X == 0 and camLoc.Y == 0 and camLoc.Z == 0) then
            pcall(function()
                camLoc = player:K2_GetActorLocation()
                if camLoc then
                    camLoc = { X = camLoc.X, Y = camLoc.Y, Z = camLoc.Z + 70 }
                end
            end)
            if not camLoc or (camLoc.X == 0 and camLoc.Y == 0 and camLoc.Z == 0) then return end
        end

        local currentRot = pc:GetControlRotation()
        if not currentRot then return end

        local usePrediction = (cfg.AIM_PREDICTION == 1)
        local predMaxTime = tonumber(cfg.PREDICTION_MAX_TIME) or 0.4
        local predStrength = tonumber(cfg.PREDICTION_STRENGTH) or 30
        local smoothAlpha = (tonumber(cfg.PREDICTION_SMOOTH) or 40) / 100
        local maxPredictionDist = 3000
        local bulletSpeed = GetBulletSpeed(weapon) or (tonumber(cfg.BULLET_SPEED) or 800)
        local useDrop = (cfg.BULLET_DROP_COMP == 1)
        local dropScale = (tonumber(cfg.BULLET_DROP_SCALE) or 100) / 100
        local dropMinDist = (tonumber(cfg.BULLET_DROP_MIN_DIST) or 50) * 100
        local usePointAdapt = (cfg.AIM_POINT_ADAPT == 1)
        local pointAdaptDist = (tonumber(cfg.AIM_POINT_DIST) or 60) * 100
        local useLock = (cfg.TARGET_LOCK == 1)
        local lockFovFactor = tonumber(cfg.LOCK_FOV_FACTOR) or 1.6

        local function EvaluateTarget(target)
            if not Valid(target) then return nil end
            if not IsEnemyVisible(pc, target) then return nil end
            if aimKnock then
                if IsKnocked(target) then
                    local hp = target.Health or 0
                    if hp <= 0 then return nil end
                end
            else
                if IsKnocked(target) then return nil end
            end
            if not aimBot and AimIsBot(target) then return nil end
            local distToEnemy = player:GetDistanceTo(target)
            if distToEnemy > currentMaxDist then return nil end
            if (mode == 3 or mode == 4) and noAimDist > 0 and
               distToEnemy < noAimDistUnits then return nil end

            local aimBone = selBoneName
            if usePointAdapt and boneIdx == 0 and distToEnemy > pointAdaptDist then
                aimBone = "spine_03"
            end

            local tPos = GetTargetBonePos(target, aimBone)
            if not tPos or (tPos.X == 0 and tPos.Y == 0 and tPos.Z == 0) then
                tPos = GetFallbackBonePos(target, boneIdx)
            end
            if not tPos or (tPos.X == 0 and tPos.Y == 0 and tPos.Z == 0) then return nil end

            if usePrediction then
                local velocity = AimGetTargetVelocity(target)
                if velocity then
                    velocity = GetSmoothedVelocity(target, velocity, smoothAlpha)
                    local flightTime = distToEnemy / (bulletSpeed * 100)
                    local predTime = math.min(flightTime * (predStrength / 100), predMaxTime)
                    tPos = GetPredictedPosition(tPos, velocity, predTime, maxPredictionDist)
                end
            end
            if useDrop and dropScale > 0 and distToEnemy > dropMinDist then
                local tSec = distToEnemy / (bulletSpeed * 100)
                local dropCm = 0.5 * 9.8 * tSec * tSec * 100 * dropScale
                if dropCm > 300 then dropCm = 300 end
                if dropCm > 0 then
                    tPos = { X = tPos.X, Y = tPos.Y, Z = tPos.Z + dropCm }
                end
            end

            local rot = KismetMathLibrary.FindLookAtRotation(camLoc, tPos)
            if not rot then return nil end

            local deltaYaw = rot.Yaw - currentRot.Yaw
            local deltaPitch = rot.Pitch - currentRot.Pitch
            if deltaYaw > 180 then deltaYaw = deltaYaw - 360 end
            if deltaYaw < -180 then deltaYaw = deltaYaw + 360 end
            if deltaPitch > 180 then deltaPitch = deltaPitch - 360 end
            if deltaPitch < -180 then deltaPitch = deltaPitch + 360 end

            local distScreen = math.sqrt(deltaYaw * deltaYaw + deltaPitch * deltaPitch)

            local score
            if priority == 0 then
                score = (distScreen / fovVal) * 0.6 + (distToEnemy / currentMaxDist) * 0.4
            elseif priority == 1 then
                score = distScreen
            else
                score = distToEnemy
            end

            return { pos = tPos, rot = rot, dist = distToEnemy, screen = distScreen, score = score }
        end

        local lockedCand = nil
        if useLock and Valid(_G.AimLockTarget) then
            local cand = EvaluateTarget(_G.AimLockTarget)
            if cand and cand.screen <= fovVal * lockFovFactor then
                lockedCand = cand
            else
                _G.AimLockTarget = nil
            end
        end

        if lockedCand then
            bestTarget = _G.AimLockTarget
            bestPos = lockedCand.pos
            bestDist = lockedCand.dist
            bestScore = lockedCand.score
        else
            for _, target in ipairs(enemies) do
                local cand = EvaluateTarget(target)
                if cand and cand.screen <= fovVal then
                    if cand.score < bestScore then
                        bestScore = cand.score
                        bestTarget = target
                        bestPos = cand.pos
                        bestDist = cand.dist
                    end
                end
            end
            if useLock and Valid(bestTarget) then
                _G.AimLockTarget = bestTarget
            end
        end

        if not Valid(bestTarget) then _G.AimBotCurrentTarget = nil return end
        if not bestPos then _G.AimBotCurrentTarget = nil return end
        _G.AimBotCurrentTarget = bestTarget

        if isFiring then
            fireCount = fireCount + 1
            lastFireTick = now
        else
            fireCount = 0
        end

        if cfg.RECOIL_RAMP == 1 and recoilVal > 0 and isFiring then
            local rampFrames = 15
            local rampFactor = 0.6 + 0.6 * math.min(fireCount / rampFrames, 1.0)
            recoilVal = recoilVal * rampFactor
        end

        local rot = KismetMathLibrary.FindLookAtRotation(camLoc, bestPos)
        if not rot then return end

        local deltaYaw = rot.Yaw - currentRot.Yaw
        local deltaPitch = rot.Pitch - currentRot.Pitch
        if deltaYaw > 180 then deltaYaw = deltaYaw - 360 end
        if deltaYaw < -180 then deltaYaw = deltaYaw + 360 end
        if deltaPitch > 180 then deltaPitch = deltaPitch - 360 end
        if deltaPitch < -180 then deltaPitch = deltaPitch + 360 end

        local angleDiff = math.sqrt(deltaYaw * deltaYaw + deltaPitch * deltaPitch)

        local deadzone = tonumber(cfg.AIM_DEADZONE) or 0.06
        if angleDiff < deadzone then return end

        local distFactor = math.min(bestDist / 30000, 1.0)
        local speed = speedVal * (0.6 + 0.4 * (1 - distFactor))
        if angleDiff > 30 then speed = speed * 1.2
        elseif angleDiff < 5 then speed = speed * 0.8 end
        speed = math.min(math.max(speed, 5), speedVal * 1.5)

        local useSnap = (cfg.AIM_SNAP == 1)
        local snapAngle = tonumber(cfg.AIM_SNAP_ANGLE) or 0.2
        local pitchSpeedFactor = tonumber(cfg.PITCH_SPEED_FACTOR) or 1.0
        if pitchSpeedFactor <= 0 then pitchSpeedFactor = 1.0 end

        local finalPitch, finalYaw
        if useSnap and angleDiff < snapAngle then
            finalPitch = rot.Pitch
            finalYaw = rot.Yaw
        else
            local smoothFactor = math.min(speed / 100, 1.0)
            finalPitch = currentRot.Pitch + (deltaPitch * smoothFactor * pitchSpeedFactor)
            finalYaw = currentRot.Yaw + (deltaYaw * smoothFactor)
        end

        if recoilVal > 0 and isFiring then
            local distFactorRecoil = math.min(bestDist / 50000, 1.0)
            local dynamicRecoil = recoilVal * (0.5 + 0.5 * distFactorRecoil)
            if dynamicRecoil > 0 then
                local pullDownForce = (dynamicRecoil / 50.0) * 1.0
                finalPitch = finalPitch - pullDownForce
            end
        end

        pc:SetControlRotation({ Pitch = finalPitch, Yaw = finalYaw, Roll = 0 }, "AimTouch")
    end)
end

-- ============================================================
-- FOV 圈
-- ============================================================
_G.FovCircleOverlay = _G.FovCircleOverlay or {
    Container = nil, WidgetSlot = nil, ParentCanvas = nil,
    Lines = {}, NumSegments = 45, Thickness = 1.5,
    LastRadius = -1, LastColor = -1, LastVisState = -1, LastCX = -1, LastCY = -1,
    PrecalcMath = nil,
    CanvasTransform = { scaleX = 1.0, scaleY = 1.0, offsetX = 0.0, offsetY = 0.0 }
}
local function GetFOVColor(idx)
    if idx == 1 then return 1.0, 0.0, 0.0 end
    if idx == 2 then return 0.0, 1.0, 0.0 end
    if idx == 3 then return 0.0, 0.0, 1.0 end
    if idx == 4 then return 1.0, 1.0, 0.0 end
    if idx == 5 then return 0.65, 0.15, 1.0 end
    if idx == 6 then return 0.0, 1.0, 1.0 end
    if idx == 7 then return 1.0, 1.0, 1.0 end
    return 1.0, 1.0, 1.0
end
local function GetFovTargetVisible(pc, target)
    if not Valid(pc) or not Valid(target) then return false end
    local now = os.clock()
    if target._fovVisTime and (now - target._fovVisTime) < 0.3 then
        return target._fovVisCached or false
    end
    target._fovVisTime = now
    local bVis = false
    pcall(function()
        if pc.LineOfSightTo then bVis = pc:LineOfSightTo(target) end
    end)
    target._fovVisCached = bVis
    return bVis
end
local function ProjectWorldToScreen(pc, worldPos)
    local sx, sy = nil, nil
    pcall(function()
        local ok, sp = pc:ProjectWorldLocationToScreen(worldPos)
        if ok and sp and sp.X ~= nil then sx, sy = sp.X, sp.Y end
    end)
    if sx == nil then
        pcall(function()
            local FVector2D_ = import("Vector2D") or _G.FVector2D
            local sp = FVector2D_ and FVector2D_(0, 0) or { X = 0, Y = 0 }
            local ok = pc:ProjectWorldLocationToScreen(worldPos, sp)
            if ok and sp and sp.X ~= nil then sx, sy = sp.X, sp.Y end
        end)
    end
    return sx, sy
end
local function GetEnemyHeadPos(target)
    if not Valid(target) then return nil end
    local tPos = GetTargetBonePos(target, "head")
    if not tPos or (tPos.X == 0 and tPos.Y == 0 and tPos.Z == 0) then
        tPos = GetFallbackBonePos(target, 0)
    end
    if not tPos or (tPos.X == 0 and tPos.Y == 0 and tPos.Z == 0) then return nil end
    return tPos
end

function _G.FovCircleOverlay.PickDynamicTarget(pc, player)
    local target = _G.AimBotCurrentTarget
    if target and slua.isValid(target) and target ~= player then
        local alive = true
        if type(target.IsAlive) == "function" then
            pcall(function() alive = target:IsAlive() end)
        end
        if alive and not IsKnocked(target) then return target end
    end
    local enemies = _G.GetEnemyTargetsFromActors(30000)
    if not enemies or #enemies == 0 then return nil end
    local best, bestScore = nil, 99999999
    local camLoc = nil
    pcall(function()
        if type(pc.GetCameraLocation) == "function" then
            camLoc = pc:GetCameraLocation()
        elseif pc.PlayerCameraManager and
               type(pc.PlayerCameraManager.GetCameraLocation) == "function" then
            camLoc = pc.PlayerCameraManager:GetCameraLocation()
        end
    end)
    if not camLoc or (camLoc.X == 0 and camLoc.Y == 0 and camLoc.Z == 0) then return nil end
    local currentRot = pc:GetControlRotation()
    if not currentRot then return nil end
    local KismetMathLibrary = import("KismetMathLibrary")
    for _, e in ipairs(enemies) do
        if Valid(e) and e ~= player then
            local alive = true
            if type(e.IsAlive) == "function" then
                pcall(function() alive = e:IsAlive() end)
            end
            if alive and not IsKnocked(e) then
                local tPos = GetEnemyHeadPos(e)
                if tPos then
                    local rot = KismetMathLibrary.FindLookAtRotation(camLoc, tPos)
                    if rot then
                        local dYaw = rot.Yaw - currentRot.Yaw
                        local dPitch = rot.Pitch - currentRot.Pitch
                        if dYaw > 180 then dYaw = dYaw - 360 end
                        if dYaw < -180 then dYaw = dYaw + 360 end
                        if dPitch > 180 then dPitch = dPitch - 360 end
                        if dPitch < -180 then dPitch = dPitch + 360 end
                        local score = math.sqrt(dYaw * dYaw + dPitch * dPitch)
                        if score < bestScore then bestScore = score best = e end
                    end
                end
            end
        end
    end
    return best
end

local function GetMainCanvas()
    local ParentCanvas = nil
    pcall(function()
        local InGameUITools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
        local MainUI = InGameUITools.GetMainControlBaseUI()
        if slua.isValid(MainUI) then
            if slua.isValid(MainUI.CanvasPanel_0) then
                ParentCanvas = MainUI.CanvasPanel_0
            elseif slua.isValid(MainUI.CanvasPanel_42) then
                ParentCanvas = MainUI.CanvasPanel_42
            end
        end
    end)
    return ParentCanvas
end

local FovCanvasLastRefresh = 0
function _G.FovCircleOverlay.RefreshCanvas()
    local now = os.clock()
    if now - FovCanvasLastRefresh < 0.5 then
        return _G.FovCircleOverlay.ParentCanvas
    end
    FovCanvasLastRefresh = now
    local canvas = GetMainCanvas()
    if canvas and slua.isValid(canvas) then
        _G.FovCircleOverlay.ParentCanvas = canvas
    end
    return _G.FovCircleOverlay.ParentCanvas
end

local function DestroyFovContainer()
    if _G.FovCircleOverlay.Container then
        pcall(function()
            if slua.isValid(_G.FovCircleOverlay.Container) then
                _G.FovCircleOverlay.Container:RemoveFromParent()
                _G.FovCircleOverlay.Container:ConditionalBeginDestroy()
            end
        end)
    end
    _G.FovCircleOverlay.Container = nil
    _G.FovCircleOverlay.WidgetSlot = nil
    _G.FovCircleOverlay.Lines = {}
    _G.FovCircleOverlay.LastRadius = -1
    _G.FovCircleOverlay.LastColor = -1
    _G.FovCircleOverlay.LastVisState = -1
    _G.FovCircleOverlay.LastCX = -1
    _G.FovCircleOverlay.LastCY = -1
end

function _G.FovCircleOverlay.Create()
    local ParentCanvas = _G.FovCircleOverlay.RefreshCanvas()
    if _G.FovCircleOverlay.Container and slua.isValid(_G.FovCircleOverlay.Container) then
        if ParentCanvas and slua.isValid(ParentCanvas) then
            local parent = nil
            pcall(function() parent = _G.FovCircleOverlay.Container:GetParent() end)
            if parent and slua.isValid(parent) and parent == ParentCanvas then
                return true
            end
            DestroyFovContainer()
        else
            return true
        end
    end
    if not ParentCanvas or not slua.isValid(ParentCanvas) then return false end
    _G.FovCircleOverlay.ParentCanvas = ParentCanvas
    local Container = nil
    pcall(function()
        Container = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", ParentCanvas)
    end)
    if not Container or not slua.isValid(Container) then return false end
    local FVector2D_ = import("Vector2D") or _G.FVector2D
    for i = 1, _G.FovCircleOverlay.NumSegments do
        local border = nil
        pcall(function()
            border = CGame:NewObjectFromPath("/Script/UMG.Border", Container)
        end)
        if border and slua.isValid(border) then
            pcall(function()
                border.RenderTransformPivot = FVector2D_(0, 0.5)
                border:SetRenderTransformPivot(FVector2D_(0, 0.5))
                border:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            end)
            local slot = Container:AddChildToCanvas(border)
            if slot then
                pcall(function() slot:SetAlignment(FVector2D_(0, 0.5)) end)
            end
            _G.FovCircleOverlay.Lines[i] = { widget = border, slot = slot }
        end
    end
    local MainSlot = nil
    pcall(function() MainSlot = ParentCanvas:AddChildToCanvas(Container) end)
    if MainSlot then
        pcall(function()
            MainSlot:SetAutoSize(false)
            MainSlot:SetSize(FVector2D_(0, 0))
            MainSlot:SetZOrder(995)
            MainSlot:SetAlignment(FVector2D_(0, 0))
            MainSlot:SetPosition(FVector2D_(0, 0))
        end)
    end
    _G.FovCircleOverlay.Container = Container
    _G.FovCircleOverlay.WidgetSlot = MainSlot
    return true
end

function _G.FovCircleOverlay.UpdateCanvasTransform(pc)
    local CT = _G.FovCircleOverlay.CanvasTransform
    if not CT then
        CT = { scaleX = 1.0, scaleY = 1.0, offsetX = 0.0, offsetY = 0.0 }
        _G.FovCircleOverlay.CanvasTransform = CT
    end
    local cg = nil
    local canvas = _G.FovCircleOverlay.ParentCanvas
    if not canvas or not slua.isValid(canvas) then
        local ParentCanvas = nil
        pcall(function()
            local InGameUITools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
            local MainUI = InGameUITools.GetMainControlBaseUI()
            if slua.isValid(MainUI) then
                if slua.isValid(MainUI.CanvasPanel_0) then
                    ParentCanvas = MainUI.CanvasPanel_0
                elseif slua.isValid(MainUI.CanvasPanel_42) then
                    ParentCanvas = MainUI.CanvasPanel_42
                end
            end
        end)
        canvas = ParentCanvas
        if canvas and slua.isValid(canvas) then
            _G.FovCircleOverlay.ParentCanvas = canvas
        end
    end
    pcall(function()
        if canvas and slua.isValid(canvas) then cg = canvas:GetCachedGeometry() end
    end)
    local FVector2D_ = import("Vector2D") or _G.FVector2D
    local success = false
    if not success and cg then
        pcall(function()
            local SBL = import("SlateBlueprintLibrary") or _G.SlateBlueprintLibrary
            if SBL and SBL.AbsoluteToLocal then
                local pt0 = SBL.AbsoluteToLocal(cg, FVector2D_ and FVector2D_(0, 0) or {X=0, Y=0})
                local pt1 = SBL.AbsoluteToLocal(cg, FVector2D_ and FVector2D_(100, 100) or {X=100, Y=100})
                if pt0 and pt1 then
                    CT.scaleX = (pt1.X - pt0.X) / 100
                    CT.scaleY = (pt1.Y - pt0.Y) / 100
                    CT.offsetX = pt0.X
                    CT.offsetY = pt0.Y
                    success = true
                end
            end
        end)
    end
    if not success and cg then
        pcall(function()
            local WLL = import("WidgetLayoutLibrary") or
                import("/Script/UMG.WidgetLayoutLibrary") or _G.WidgetLayoutLibrary
            if WLL and WLL.ScreenToWidgetLocal then
                local pt0 = FVector2D_ and FVector2D_(0, 0) or {X=0, Y=0}
                local pt1 = FVector2D_ and FVector2D_(0, 0) or {X=0, Y=0}
                WLL.ScreenToWidgetLocal(pc, cg, FVector2D_ and FVector2D_(0, 0) or {X=0, Y=0}, pt0)
                WLL.ScreenToWidgetLocal(pc, cg, FVector2D_ and FVector2D_(100, 100) or {X=100, Y=100}, pt1)
                if (pt1.X - pt0.X) ~= 0 or (pt1.Y - pt0.Y) ~= 0 then
                    CT.scaleX = (pt1.X - pt0.X) / 100
                    CT.scaleY = (pt1.Y - pt0.Y) / 100
                    CT.offsetX = pt0.X
                    CT.offsetY = pt0.Y
                    success = true
                end
            end
        end)
    end
    if not success then
        local scale = 1.0
        pcall(function()
            local WLL = import("WidgetLayoutLibrary") or
                import("/Script/UMG.WidgetLayoutLibrary") or _G.WidgetLayoutLibrary
            if WLL and WLL.GetViewportScale then
                scale = WLL.GetViewportScale(pc) or 1.0
                if type(scale) ~= "number" or scale <= 0 then scale = 1.0 end
            end
        end)
        CT.scaleX = 1.0 / scale
        CT.scaleY = 1.0 / scale
        CT.offsetX = 0
        CT.offsetY = 0
    end
end

function _G.FovCircleOverlay.Update(pc, player)
    local cfg = _G.AimBotConfig
    if not cfg or cfg.FOV_CIRCLE ~= 1 then
        if _G.FovCircleOverlay.Container and slua.isValid(_G.FovCircleOverlay.Container) then
            pcall(function()
                _G.FovCircleOverlay.Container:SetWidgetVisibility(
                    UEnums.ESlateVisibility.Collapsed)
            end)
            _G.FovCircleOverlay.LastRadius = -1
        end
        return
    end
    if not Valid(pc) or not Valid(player) then return end

    local isADS = player.bIsGunADS or false
    local isFiring = player.bIsWeaponFiring or false
    local fovVal = cfg.HIP_FOV or 20
    if isADS and not isFiring and cfg.SCOPE_AIM == 1 then
        fovVal = cfg.SCOPE_FOV or 8
    elseif isADS and isFiring and cfg.SCOPE_FIRE_AIM == 1 then
        fovVal = cfg.SCOPE_FIRE_FOV or 8
    elseif isFiring and cfg.FIRE_AIM == 1 then
        fovVal = cfg.FIRE_FOV or 20
    elseif cfg.HIP_AIM == 1 then
        fovVal = cfg.HIP_FOV or 20
    end

    local colIdx = tonumber(cfg.FOV_CIRCLE_COLOR) or 7
    if colIdx < 1 or colIdx > 7 then colIdx = 7 end
    local thickness = tonumber(cfg.FOV_CIRCLE_THICKNESS) or 2
    if thickness < 1 then thickness = 1 end

    local vpX, vpY = 1920, 1080
    pcall(function()
        local ui_util = require("client.common.ui_util")
        if ui_util and ui_util.GetViewportSize then
            local vp = ui_util.GetViewportSize()
            if vp and vp.X and vp.X > 100 then vpX = vp.X; vpY = vp.Y end
        end
    end)
    if vpX <= 100 then
        pcall(function()
            local WLL = import("WidgetLayoutLibrary") or
                import("/Script/UMG.WidgetLayoutLibrary")
            if WLL and WLL.GetViewportSize then
                local sz = WLL.GetViewportSize(pc)
                if sz and sz.X and sz.X > 100 then vpX = sz.X; vpY = sz.Y end
            end
        end)
    end

    pcall(function() _G.FovCircleOverlay.UpdateCanvasTransform(pc) end)
    local CT = _G.FovCircleOverlay.CanvasTransform
    if not CT then
        CT = { scaleX = 1.0, scaleY = 1.0, offsetX = 0.0, offsetY = 0.0 }
        _G.FovCircleOverlay.CanvasTransform = CT
    end
    local scaleX = CT.scaleX or 1.0
    local scaleY = CT.scaleY or 1.0
    local offsetX = CT.offsetX or 0
    local offsetY = CT.offsetY or 0

    local fovMode = tonumber(cfg.FOV_CIRCLE_MODE) or 0
    local centerX, centerY, targetRadius
    local visTarget = nil

    if fovMode == 1 then
        local target = _G.FovCircleOverlay.PickDynamicTarget(pc, player)
        visTarget = target
        if not target then
            if _G.FovCircleOverlay.Container and slua.isValid(_G.FovCircleOverlay.Container) then
                pcall(function()
                    _G.FovCircleOverlay.Container:SetWidgetVisibility(
                        UEnums.ESlateVisibility.Collapsed)
                end)
                _G.FovCircleOverlay.LastRadius = -1
            end
            return
        end
        local tPos = GetEnemyHeadPos(target)
        if not tPos then
            if _G.FovCircleOverlay.Container and slua.isValid(_G.FovCircleOverlay.Container) then
                pcall(function()
                    _G.FovCircleOverlay.Container:SetWidgetVisibility(
                        UEnums.ESlateVisibility.Collapsed)
                end)
                _G.FovCircleOverlay.LastRadius = -1
            end
            return
        end
        local sx, sy = ProjectWorldToScreen(pc, tPos)
        if not sx or sy == nil
           or sx < -50 or sy < -50 or sx > vpX + 50 or sy > vpY + 50 then
            if _G.FovCircleOverlay.Container and slua.isValid(_G.FovCircleOverlay.Container) then
                pcall(function()
                    _G.FovCircleOverlay.Container:SetWidgetVisibility(
                        UEnums.ESlateVisibility.Collapsed)
                end)
                _G.FovCircleOverlay.LastRadius = -1
            end
            return
        end
        centerX = sx * scaleX + offsetX
        centerY = sy * scaleY + offsetY
        targetRadius = (fovVal / 100.0) * (vpX / 2.0) * scaleX
    else
        local rawCX = vpX * 0.5
        local rawCY = vpY * 0.5
        local rawRadius = (fovVal / 100.0) * (vpX / 2.0)
        targetRadius = rawRadius * scaleX
        centerX = rawCX * scaleX + offsetX
        centerY = rawCY * scaleY + offsetY
    end

    local visState = -1
    local visMode = tonumber(cfg.FOV_CIRCLE_VIS_MODE) or 0
    if visMode == 1 then
        if not visTarget then
            visTarget = _G.FovCircleOverlay.PickDynamicTarget(pc, player)
        end
        if visTarget then
            local bVis = GetFovTargetVisible(pc, visTarget)
            visState = bVis and 1 or 0
            if bVis then
                colIdx = tonumber(cfg.FOV_CIRCLE_VIS_COLOR) or 2
                if colIdx < 1 or colIdx > 7 then colIdx = 2 end
            else
                colIdx = tonumber(cfg.FOV_CIRCLE_COVER_COLOR) or 1
                if colIdx < 1 or colIdx > 7 then colIdx = 1 end
            end
        end
    end

    if _G.FovCircleOverlay.Container and slua.isValid(_G.FovCircleOverlay.Container) then
        local parent = nil
        pcall(function() parent = _G.FovCircleOverlay.Container:GetParent() end)
        if not parent or not slua.isValid(parent) then
            DestroyFovContainer()
        end
    end

    if not _G.FovCircleOverlay.Create() then return end
    pcall(function()
        _G.FovCircleOverlay.Container:SetWidgetVisibility(
            UEnums.ESlateVisibility.SelfHitTestInvisible)
    end)

    if math.abs(_G.FovCircleOverlay.LastRadius - targetRadius) < 0.5
       and _G.FovCircleOverlay.LastColor == colIdx
       and _G.FovCircleOverlay.LastVisState == visState
       and math.abs(_G.FovCircleOverlay.LastCX - centerX) < 0.5
       and math.abs(_G.FovCircleOverlay.LastCY - centerY) < 0.5 then
        return
    end

    _G.FovCircleOverlay.LastRadius = targetRadius
    _G.FovCircleOverlay.LastColor = colIdx
    _G.FovCircleOverlay.LastVisState = visState
    _G.FovCircleOverlay.LastCX = centerX
    _G.FovCircleOverlay.LastCY = centerY

    local FLinearColor_ = import("LinearColor") or _G.FLinearColor
    local r, g, b = GetFOVColor(colIdx)
    local dim = 0.55
    local color = FLinearColor_ and FLinearColor_(r * dim, g * dim, b * dim, 1.0)
        or {R=r*dim*255, G=g*dim*255, B=b*dim*255, A=255}
    local numSegments = _G.FovCircleOverlay.NumSegments

    if not _G.FovCircleOverlay.PrecalcMath then
        _G.FovCircleOverlay.PrecalcMath = {}
        local angleStep = 360.0 / numSegments
        local math_cos, math_sin, math_rad = math.cos, math.sin, math.rad
        local math_atan2 = math.atan2 or math.atan
        for i = 1, numSegments do
            local angle1 = math_rad((i - 1) * angleStep)
            local angle2 = math_rad(i * angleStep)
            local c1, s1 = math_cos(angle1), math_sin(angle1)
            local c2, s2 = math_cos(angle2), math_sin(angle2)
            local dx_unit = c2 - c1
            local dy_unit = s2 - s1
            local dist_unit = math.sqrt(dx_unit*dx_unit + dy_unit*dy_unit)
            local angleDeg = math.deg(math_atan2(dy_unit, dx_unit))
            _G.FovCircleOverlay.PrecalcMath[i] = {
                c1 = c1, s1 = s1, dist_unit = dist_unit, angleDeg = angleDeg
            }
        end
    end

    pcall(function()
        local FVector2D_ = import("Vector2D") or _G.FVector2D
        for i = 1, numSegments do
            local md = _G.FovCircleOverlay.PrecalcMath[i]
            local x1 = targetRadius * md.c1
            local y1 = targetRadius * md.s1
            local dist = targetRadius * md.dist_unit
            local line = _G.FovCircleOverlay.Lines[i]
            if line and line.slot and slua.isValid(line.slot) then
                line.slot:SetPosition(FVector2D_(centerX + x1, centerY + y1))
                line.slot:SetSize(FVector2D_(dist + 0.8, thickness))
                line.widget:SetRenderAngle(md.angleDeg)
                line.widget:SetBrushColor(color)
            end
        end
    end)
end

function _G.CleanUpFovCircleOverlay()
    if _G.FovCircleOverlay then DestroyFovContainer() end
end

-- ============================================================
-- 定时器
-- ============================================================
local function FovCircleTick()
    _G.FOVCIRCLE_LAST_TICK = os.clock()
    pcall(function()
        local pc = slua_GameFrontendHUD:GetPlayerController()
        if not Valid(pc) then return end
        local player = GameplayData.GetPlayerCharacter()
        if not Valid(player) then return end
        _G.FovCircleOverlay.Update(pc, player)
    end)
end

local function StartFovCircleTimer(force)
    local tmr = slua_GameFrontendHUD:GetPlayerController()
    if not Valid(tmr) then
        tmr = import("GameplayStatics").GetPlayerController(
            slua_GameFrontendHUD:GetWorld(), 0)
    end
    if not Valid(tmr) then return end
    if force then _G.FOVCIRCLE_TIMER = nil end
    if _G.FOVCIRCLE_TIMER and Valid(_G.FOVCIRCLE_TIMER) then return end
    _G.FOVCIRCLE_TIMER = tmr
    tmr:AddGameTimer(0.1, false, function()
        local pc = slua_GameFrontendHUD:GetPlayerController()
        if Valid(pc) then
            pc:AddGameTimer(0.05, true, FovCircleTick)
        end
    end)
end

local function StartAimTouchTimer(force)
    local tmr = slua_GameFrontendHUD:GetPlayerController()
    if not Valid(tmr) then
        tmr = import("GameplayStatics").GetPlayerController(
            slua_GameFrontendHUD:GetWorld(), 0)
    end
    if not Valid(tmr) then return end
    if force then _G.AIMTOUCH_TIMER = nil end
    if _G.AIMTOUCH_TIMER == tmr then return end
    _G.AIMTOUCH_TIMER = tmr
    tmr:AddGameTimer(0.1, false, function()
        local pc = slua_GameFrontendHUD:GetPlayerController()
        if Valid(pc) then
            pc:AddGameTimer(0.025, true, _G.AimTouch)
        end
    end)
end

local function EnsureAimTouchAlive()
    pcall(function()
        local last = _G.AIMTOUCH_LAST_TICK or 0
        if os.clock() - last > 1.5 then
            StartAimTouchTimer(true)
        end
    end)
end
local function EnsureFovCircleAlive()
    pcall(function()
        local last = _G.FOVCIRCLE_LAST_TICK or 0
        if os.clock() - last > 1.5 then
            StartFovCircleTimer(true)
        end
    end)
    EnsureAimTouchAlive()
end
local function StartFovCircleSelfHeal()
    if _G.FOVCIRCLE_SELFHEAL_STARTED then return end
    _G.FOVCIRCLE_SELFHEAL_STARTED = true
    pcall(function()
        if Game and Game.SetTimer then
            Game:SetTimer(1.0, true, EnsureFovCircleAlive)
        end
    end)
end

-- ============================================================
-- 主循环
-- ============================================================
local rangeLastApply = 0
local tickCount = 0
local function MainTick()
    tickCount = tickCount + 1
    if tickCount % 30 == 0 then
        meshCache = {}
        outlineState = {}
    end
    pcall(UpdateOutlines)
    pcall(DJWallV3.DJWallhack)
    pcall(InfoESP)
    pcall(DistESP)
    pcall(BoxESP)
    pcall(NativeESP)
    local now = os.clock()
    if now - rangeLastApply > 2 then
        rangeLastApply = now
        pcall(ApplyHitboxScale)
    end
    pcall(GunMainTick)
    local bcfg = _G.BasicFuncConfig
    pcall(ApplyFOV, bcfg)
    if bcfg.LOCK_FPS > 0 then
        if not unlocked then pcall(UnlockAllGraphics, bcfg) end
        pcall(LockFPS, bcfg)
    end
    pcall(ApplyPerformanceOptimization, bcfg)
end

-- ============================================================
-- 防作弊绕过
-- ============================================================
local bypassDone = false
local function InitAntiCheatBypass()
    if bypassDone then return end
    bypassDone = true
    pcall(function()
        local nop = function() end
        local GameplayCallbacks = _G.GameplayCallbacks or _G.GC
        if GameplayCallbacks then
            GameplayCallbacks.SendTssSdkAntiDataToLobby = nop
            GameplayCallbacks.SendDSErrorLogToLobby = nop
            GameplayCallbacks.SendDSHawkEyePatrolLogToLobby = nop
            GameplayCallbacks.SendSecTLog = nop
        end
        local SubsystemMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if SubsystemMgr then
            local DSHawkEyeSub = SubsystemMgr.Get("DSHawkEyePatrolSubsystem")
            if DSHawkEyeSub then DSHawkEyeSub.MarkSuspiciousPlayer = nop end
        end
        pcall(function()
            local HiggsComponent =
                package.loaded["GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent"]
            if HiggsComponent then
                HiggsComponent.ControlMHActive = nop
                HiggsComponent.Tick = nop
                HiggsComponent.TriggerAvatarCheck = nop
            end
        end)
    end)
end

-- ============================================================
-- UI 系统 v5.4 — 毛玻璃双面板 · 插画背景 · 两列网格 · 开关式 · 过渡动画
-- ============================================================
local FLinearColor = import("LinearColor")
local FVector2D = import("Vector2D")
local FAnchors = import("Anchors")
local FSlateColor = import("SlateColor") or import("/Script/SlateCore.SlateColor")
local IsValidUI = function(obj)
    return obj and slua and slua.isValid and slua.isValid(obj)
end

local BuildMenu, CreateFloat, SwitchParentTab, SwitchSubTab

-- ---------- 状态 ----------
_G.U5UIState = _G.U5UIState or {
    bgAlpha = 0.82,
    searchKeyword = "",
    dragActive = false,
    dragMouseStart = nil,
    dragMenuStart = nil,
    profile = 1,
    showPerf = 1,
    lang = "zh",
    lastValClick = 0,
    autoCentered = false,
    animating = false,
}

local _LocaleData = {
    zh = { title="综合菜单", searchHint="搜索...", allOn="全开", allOff="全关",
           tabs={"内透","绘制","范围","枪械","基本","自瞄"} },
    en = { title="Multi Menu", searchHint="Search...", allOn="ON", allOff="OFF",
           tabs={"Wall","ESP","Range","Gun","Basic","Aim"} },
}
function _G.U5L(k)
    local t = _LocaleData[_G.U5UIState.lang] or _LocaleData.zh
    return t[k] or k
end
function _G.U5LTab(i)
    local t = _LocaleData[_G.U5UIState.lang] or _LocaleData.zh
    return (t.tabs and t.tabs[i]) or tostring(i)
end

-- ---------- Tween ----------
local _tweens = {}
function _G.U5Tween(duration, from, to, setter, onDone)
    table.insert(_tweens, { t=0, d=math.max(duration,0.01), from=from, to=to,
                            setter=setter, onDone=onDone })
end
function _G.U5UpdateTweens(dt)
    for i = #_tweens, 1, -1 do
        local tw = _tweens[i]
        tw.t = tw.t + dt
        local k = math.min(tw.t / tw.d, 1)
        local e = 1 - (1-k)*(1-k)
        pcall(function() tw.setter(tw.from + (tw.to - tw.from) * e) end)
        if k >= 1 then
            if tw.onDone then pcall(tw.onDone) end
            table.remove(_tweens, i)
        end
    end
end

-- ---------- 行索引 ----------
_G.U5Rows = _G.U5Rows or {}
function _G.U5RegisterRow(pIdx, sIdx, row)
    _G.U5Rows[pIdx] = _G.U5Rows[pIdx] or {}
    _G.U5Rows[pIdx][sIdx] = _G.U5Rows[pIdx][sIdx] or {}
    table.insert(_G.U5Rows[pIdx][sIdx], row)
end
function _G.U5RefreshAllRows()
    for _, subs in pairs(_G.U5Rows) do
        for _, rows in pairs(subs) do
            for _, r in ipairs(rows) do
                if r.refresh then pcall(r.refresh) end
            end
        end
    end
end
_G.U5Defaults = _G.U5Defaults or {}

-- ---------- 预设 ----------
_G.U5Profiles = _G.U5Profiles or { profiles = {}, current = 1 }
function _G.U5SaveProfile(idx)
    idx = idx or _G.U5Profiles.current
    local function cp(t) local o={} for k,v in pairs(t) do o[k]=v end return o end
    _G.U5Profiles.profiles[idx] = {
        U5Config        = cp(_G.U5Config),
        U5ESPConfig     = cp(_G.U5ESPConfig),
        U5RangeConfig   = cp(_G.U5RangeConfig),
        GunFuncConfig   = cp(_G.GunFuncConfig),
        BasicFuncConfig = cp(_G.BasicFuncConfig),
        AimBotConfig    = cp(_G.AimBotConfig),
    }
    print("[U5] 预设 "..idx.." 已保存")
end
function _G.U5LoadProfile(idx)
    idx = idx or _G.U5Profiles.current
    local p = _G.U5Profiles.profiles[idx]
    if not p then print("[U5] 预设 "..idx.." 为空") return end
    local function cp(dst, src) for k,v in pairs(src) do dst[k]=v end end
    cp(_G.U5Config,        p.U5Config)
    cp(_G.U5ESPConfig,     p.U5ESPConfig)
    cp(_G.U5RangeConfig,   p.U5RangeConfig)
    cp(_G.GunFuncConfig,   p.GunFuncConfig)
    cp(_G.BasicFuncConfig, p.BasicFuncConfig)
    cp(_G.AimBotConfig,    p.AimBotConfig)
    if _G.ConfigAutoSave then _G.ConfigAutoSave:SaveAll() end
    _G.U5RefreshAllRows()
end

function _G.U5RGB255(r,g,b,a)
    return FLinearColor((r or 0)/255, (g or 0)/255, (b or 0)/255, a or 1.0)
end

-- ---------- 主题色 ----------
local TAB_ACCENTS = {
    {1.000, 0.220, 0.560},
    {0.180, 0.920, 1.000},
    {1.000, 0.580, 0.180},
    {1.000, 0.920, 0.280},
    {0.200, 1.000, 0.560},
    {0.780, 0.380, 1.000},
}
local function AccentColor(tabIdx, a)
    local t = TAB_ACCENTS[tabIdx] or TAB_ACCENTS[1]
    return FLinearColor(t[1], t[2], t[3], a or 1.0)
end
local function AccentDim(tabIdx, alpha)
    -- v5.4 轻主题：淡彩（混白）用于浅色底
    local t = TAB_ACCENTS[tabIdx] or TAB_ACCENTS[1]
    return FLinearColor(t[1]*0.38 + 0.62, t[2]*0.38 + 0.62, t[3]*0.38 + 0.62, alpha or 1.0)
end
local function AccentDeep(tabIdx, alpha)
    -- v5.4 轻主题：加深的强调色（用于浅底上的文字/滑块）
    local t = TAB_ACCENTS[tabIdx] or TAB_ACCENTS[1]
    return FLinearColor(t[1]*0.70, t[2]*0.70, t[3]*0.70, alpha or 1.0)
end
local function AccentBright(tabIdx, alpha)
    local t = TAB_ACCENTS[tabIdx] or TAB_ACCENTS[1]
    return FLinearColor(
        math.min(1, t[1]*1.3 + 0.15),
        math.min(1, t[2]*1.3 + 0.15),
        math.min(1, t[3]*1.3 + 0.15),
        alpha or 1.0)
end

local C = {
    bg_main      = FLinearColor(0.930, 0.945, 0.980, 0.860),
    bg_panel     = FLinearColor(0.955, 0.965, 0.990, 0.940),
    bg_header    = FLinearColor(0.905, 0.925, 0.965, 0.660),
    bg_row       = FLinearColor(0.885, 0.910, 0.950, 0.820),
    bg_row_alt   = FLinearColor(0.845, 0.880, 0.930, 0.820),
    bg_row_hover = FLinearColor(0.775, 0.830, 0.905, 0.900),
    bg_side      = FLinearColor(0.880, 0.905, 0.950, 0.480),
    bg_input     = FLinearColor(0.975, 0.980, 0.995, 0.920),
    text_bright  = FLinearColor(0.070, 0.090, 0.140, 1.0),
    text_normal  = FLinearColor(0.150, 0.190, 0.270, 1.0),
    text_dim     = FLinearColor(0.300, 0.345, 0.430, 1.0),
    text_muted   = FLinearColor(0.500, 0.545, 0.620, 1.0),
    green        = FLinearColor(0.050, 0.560, 0.330, 1.0),
    red          = FLinearColor(0.850, 0.200, 0.290, 1.0),
    cyan         = FLinearColor(0.040, 0.500, 0.660, 1.0),
    magenta      = FLinearColor(0.780, 0.150, 0.480, 1.0),
    border       = FLinearColor(0.760, 0.795, 0.865, 0.900),
    border_lit   = FLinearColor(0.280, 0.500, 0.820, 1.0),
    divider      = FLinearColor(0.700, 0.740, 0.820, 0.550),
    shadow_deep  = FLinearColor(0.200, 0.230, 0.300, 0.300),
    transparent  = FLinearColor(0, 0, 0, 0.01),
    black        = FLinearColor(0, 0, 0, 1.0),
    grid_line    = FLinearColor(0.550, 0.600, 0.700, 0.100),
}


local RGB = { time = 0, r = 1, g = 0.3, b = 0.3 }
local function UpdateRGB()
    RGB.time = RGB.time + 0.04
    if RGB.time > 6.28 then RGB.time = 0 end
    RGB.r = 0.5 + 0.5 * math.sin(RGB.time)
    RGB.g = 0.5 + 0.5 * math.sin(RGB.time + 2.1)
    RGB.b = 0.5 + 0.5 * math.sin(RGB.time + 4.2)
end
local function RGBColor(a) return FLinearColor(RGB.r, RGB.g, RGB.b, a or 1.0) end

-- ---------- 尺寸常量 ----------
local M_W = 780
local M_H = 820
-- v5.4 视口自适应 + 毛玻璃双面板参数
local U5_DESIGN_W, U5_DESIGN_H = 1267, 799
local U5_LEFT_FRAC, U5_GAP_FRAC = 0.256, 0.024
local U5_ART_ALPHA = 0.60
local HEADER_H = 48
local FOOTER_H = 22
local LEFT_TAB_W = 118
local SUB_TAB_H = 38
local CELL_H = 38
local COL_GAP = 6
local ROW_PAD = 8

local parentCanvas, bgPanel = nil, nil
local floatItem = nil
local isMenuOpen, menuBuilt = false, false
local menuX, menuY = 30, 30
local allWidgets = {}
local rgbWidgets = {}
local pulseWidgets = {}
local dataDots = {}

local NUM_PARENT_TABS = 6
local currentParentTab = 1
local currentSubTab = {1, 1, 1, 1, 1, 1}
local parentTabButtons = {}
local subTabButtons = {{}, {}, {}, {}, {}, {}}
local subTabPanels = {{}, {}, {}, {}, {}, {}}
local subTabScrollBoxes = {{}, {}, {}, {}, {}, {}}

local TAB_NAMES_WALLHACK = { "敌人", "武器", "人物", "通用" }
local TAB_NAMES_ESP      = { "信息", "距离", "盒子", "原生" }
local TAB_NAMES_RANGE    = { "躯干", "手臂", "腿部", "开关" }
local TAB_NAMES_GUN      = { "基础", "射速", "聚点", "速度" }
local TAB_NAMES_BASIC    = { "视野", "画质" }
local TAB_NAMES_AIM      = { "开关", "部位", "参数", "预判", "精度", "弹道", "FOV圈" }
local PARENT_ICONS       = { "◉", "◇", "◎", "✦", "◆", "✧" }

-- ---------- 基础构建 ----------
local function GetCanvas()
    if parentCanvas and Game:IsValid(parentCanvas) then return parentCanvas end
    parentCanvas = nil
    pcall(function()
        local InGameUITools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
        local MainUI = InGameUITools.GetMainControlBaseUI()
        if not MainUI or not Game:IsValid(MainUI) then return end
        if MainUI.CanvasPanel_0 and Game:IsValid(MainUI.CanvasPanel_0) then
            parentCanvas = MainUI.CanvasPanel_0
        elseif MainUI.CanvasPanel_42 and Game:IsValid(MainUI.CanvasPanel_42) then
            parentCanvas = MainUI.CanvasPanel_42
        end
    end)
    return parentCanvas
end

local function MakeBtn(parent, x, y, w, h, z, onClick, onHover, onUnhover)
    local btn = nil
    pcall(function()
        btn = CGame:NewObjectFromPath("/Script/UMG.Button", parent)
        if btn and slua.isValid(btn) then
            pcall(function() btn:SetColorAndOpacity(C.transparent) end)
            pcall(function() btn:SetBackgroundColor(C.transparent) end)
            pcall(function()
                btn:SetWidgetVisibility(UEnums.ESlateVisibility.Visible)
            end)
            local slot = parent:AddChildToCanvas(btn)
            if slot then
                slot:SetAutoSize(false)
                slot:SetPosition(FVector2D(x, y))
                slot:SetSize(FVector2D(w, h))
                slot:SetZOrder(z or 900)
            end
            if onClick then
                pcall(function()
                    if btn.OnClicked then
                        btn.OnClicked:Add(function() pcall(onClick) end)
                    end
                end)
            end
            if onHover then
                pcall(function()
                    if btn.OnHovered then
                        btn.OnHovered:Add(function() pcall(onHover) end)
                    end
                end)
            end
            if onUnhover then
                pcall(function()
                    if btn.OnUnhovered then
                        btn.OnUnhovered:Add(function() pcall(onUnhover) end)
                    end
                end)
            end
        end
    end)
    table.insert(allWidgets, btn)
    return btn
end

local function Layer(parent, x, y, w, h, color, z, isRGB, isPulse, pulseTab)
    local b = nil
    pcall(function()
        b = CGame:NewObjectFromPath("/Script/UMG.Border", parent)
        if b and slua.isValid(b) then
            b:SetBrushColor(color)
            b:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            local slot = parent:AddChildToCanvas(b)
            if slot then
                slot:SetAutoSize(false)
                slot:SetPosition(FVector2D(x, y))
                slot:SetSize(FVector2D(w, h))
                slot:SetZOrder(z or 0)
            end
            if isRGB then table.insert(rgbWidgets, b) end
            if isPulse then
                table.insert(pulseWidgets, {
                    widget = b, base = color,
                    tab = pulseTab or 1,
                    phase = math.random() * 6.28
                })
            end
        end
    end)
    table.insert(allWidgets, b)
    return b
end

local function MakeCorners(parent, x, y, w, h, color, z, size, thickness)
    size = size or 8
    thickness = thickness or 2
    Layer(parent, x, y, size, thickness, color, z or 10)
    Layer(parent, x, y, thickness, size, color, z or 10)
    Layer(parent, x + w - size, y, size, thickness, color, z or 10)
    Layer(parent, x + w - thickness, y, thickness, size, color, z or 10)
    Layer(parent, x, y + h - thickness, size, thickness, color, z or 10)
    Layer(parent, x, y + h - size, thickness, size, color, z or 10)
    Layer(parent, x + w - size, y + h - thickness, size, thickness, color, z or 10)
    Layer(parent, x + w - thickness, y + h - size, thickness, size, color, z or 10)
end

local function MakeGradientBar(parent, x, y, w, h, color, z, leftToRight)
    local segs = 8
    local segW = w / segs
    for i = 1, segs do
        local t = leftToRight and (i / segs) or (1 - i / segs + 1 / segs)
        local a = color.A * (0.15 + 0.85 * t)
        Layer(parent, x + (i-1) * segW, y, segW + 0.5, h,
            FLinearColor(color.R, color.G, color.B, a), z)
    end
end

local function Text(parent, txt, x, y, size, color, z, alignX, alignY, bold, mono)
    local t = nil
    pcall(function()
        t = CGame:NewObjectFromPath("/Script/UMG.TextBlock", parent)
        if t and slua.isValid(t) then
            t:SetText(txt)
            if FSlateColor then t:SetColorAndOpacity(FSlateColor(color))
            else t:SetColorAndOpacity(color) end
            if t.Font then
                local f = t.Font
                f.Size = size
                if bold ~= false then
                    pcall(function() f.TypefaceFontName = "Bold" end)
                    pcall(function() f.bIsBold = true end)
                end
                if mono then
                    pcall(function() f.TypefaceFontName = "Mono" end)
                end
                t.Font = f
            end
            t:SetRenderTransformPivot(FVector2D(alignX or 0.5, alignY or 0.5))
            t:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            local slot = parent:AddChildToCanvas(t)
            if slot then
                slot:SetAutoSize(true)
                slot:SetAlignment(FVector2D(alignX or 0.5, alignY or 0.5))
                slot:SetPosition(FVector2D(x, y))
                slot:SetZOrder(z or 100)
            end
        end
    end)
    table.insert(allWidgets, t)
    return t
end

local function Divider(parent, x, y, w, color, z)
    Layer(parent, x, y, w, 1, color or C.divider, z or 5)
end

local function BuildGrid(parent, x, y, w, h, z, stepX, stepY)
    stepX = stepX or 40
    stepY = stepY or 40
    local i = 0
    while i * stepX <= w do
        Layer(parent, x + i*stepX, y, 1, h, C.grid_line, z)
        i = i + 1
    end
    i = 0
    while i * stepY <= h do
        Layer(parent, x, y + i*stepY, w, 1, C.grid_line, z)
        i = i + 1
    end
end

local function NewGrid(contentW)
    local colW = (contentW - ROW_PAD * 2 - COL_GAP) / 2
    return {
        colW = colW,
        col = 0,
        row = 0,
        next = function(self)
            local x = ROW_PAD + self.col * (self.colW + COL_GAP)
            local y = 8 + self.row * CELL_H
            local w = self.colW
            self.col = self.col + 1
            if self.col >= 2 then
                self.col = 0
                self.row = self.row + 1
            end
            return x, y, w
        end,
        fullRow = function(self)
            local x = ROW_PAD
            local y = 8 + self.row * CELL_H
            local w = contentW - ROW_PAD * 2
            self.col = 0
            self.row = self.row + 1
            return x, y, w
        end,
    }
end

local MOVE_STEP = 25
local function MoveMenu(dx, dy)
    if not bgPanel or not IsValidUI(bgPanel) then return end
    pcall(function()
        menuX = math.max(0, math.min(2600, menuX + dx))
        menuY = math.max(0, math.min(1600, menuY + dy))
        local slot = bgPanel.Slot
        if slot then slot:SetPosition(FVector2D(menuX, menuY)) end
    end)
end

local function MakeArrowBtn(parent, x, y, size, direction, arrowChar)
    Layer(parent, x + 1, y + 1, size, size, C.shadow_deep, 900)
    Layer(parent, x, y, size, size, C.border, 901)
    Layer(parent, x + 1, y + 1, size - 2, size - 2, C.bg_main, 902)
    Text(parent, arrowChar, x + size * 0.5, y + size * 0.5, 12,
        C.text_normal, 903, 0.5, 0.5)
    MakeBtn(parent, x, y, size, size, 950, function()
        if direction == "up" then MoveMenu(0, -MOVE_STEP)
        elseif direction == "down" then MoveMenu(0, MOVE_STEP)
        elseif direction == "left" then MoveMenu(-MOVE_STEP, 0)
        elseif direction == "right" then MoveMenu(MOVE_STEP, 0)
        end
    end)
end

-- ---------- 开关 ----------
local function MakeSwitch(parent, x, y, initialChecked, tabIdx)
    local sw = {}
    sw.tab = tabIdx or 1
    sw.checked = initialChecked or false
    sw.trackW, sw.trackH = 34, 18
    sw.knobSize, sw.knobPad = 14, 2
    sw.baseX, sw.baseY = x, y

    sw._glowAlpha = initialChecked and 0.75 or 0.10
    sw.glow = Layer(parent, x-4, y-4, sw.trackW+8, sw.trackH+8,
        AccentColor(sw.tab, sw._glowAlpha), 390, false, true, sw.tab)

    sw.border = Layer(parent, x, y, sw.trackW, sw.trackH, C.border, 400)
    sw.bg = Layer(parent, x+1, y+1, sw.trackW-2, sw.trackH-2,
        initialChecked and AccentDim(sw.tab, 1.0) or C.bg_input, 401)
    sw._innerAlpha = initialChecked and 0.30 or 0.0
    sw.inner = Layer(parent, x+1, y+1, sw.trackW-2, sw.trackH-2,
        AccentColor(sw.tab, sw._innerAlpha), 401)

    local knobX = initialChecked
        and (x + sw.trackW - sw.knobSize - sw.knobPad)
        or  (x + sw.knobPad)
    sw._knobX = knobX

    sw.knobGlow = Layer(parent, knobX - 3, y + sw.knobPad - 3,
        sw.knobSize + 6, sw.knobSize + 6,
        initialChecked and AccentDeep(sw.tab, 0.85) or C.transparent,
        402, false, true, sw.tab)
    sw.knob = Layer(parent, knobX, y + sw.knobPad, sw.knobSize, sw.knobSize,
        initialChecked and AccentColor(sw.tab) or C.text_muted, 404)
    return sw
end

local function SetSwitch(sw, checked, animate)
    if not sw then return end
    sw.checked = checked
    local trackW, knobSize, knobPad = sw.trackW, sw.knobSize, sw.knobPad
    local baseX, baseY = sw.baseX, sw.baseY
    local targetX = checked
        and (baseX + trackW - knobSize - knobPad)
        or  (baseX + knobPad)

    local onColor = AccentColor(sw.tab)
    local offColor = C.text_muted

    if sw.bg and IsValidUI(sw.bg) then
        pcall(function()
            sw.bg:SetBrushColor(checked and AccentDim(sw.tab, 1.0) or C.bg_input)
        end)
    end
    if sw.inner and IsValidUI(sw.inner) then
        local target = checked and 0.30 or 0.0
        pcall(function() sw.inner:SetBrushColor(AccentColor(sw.tab, target)) end)
    end
    if sw.knob and IsValidUI(sw.knob) then
        pcall(function()
            sw.knob:SetBrushColor(checked and onColor or offColor)
        end)
        local slot = sw.knob.Slot
        if slot then
            if animate then
                local startX = sw._knobX or targetX
                sw._knobX = targetX
                pcall(function()
                    _G.U5Tween(0.18, startX, targetX, function(v)
                        if sw.knob and IsValidUI(sw.knob) then
                            local s = sw.knob.Slot
                            if s then s:SetPosition(FVector2D(v, baseY + knobPad)) end
                        end
                        if sw.knobGlow and IsValidUI(sw.knobGlow) then
                            local s = sw.knobGlow.Slot
                            if s then s:SetPosition(FVector2D(v - 3, baseY + knobPad - 3)) end
                        end
                    end)
                end)
            else
                sw._knobX = targetX
                pcall(function() slot:SetPosition(FVector2D(targetX, baseY + knobPad)) end)
                if sw.knobGlow and IsValidUI(sw.knobGlow) then
                    pcall(function()
                        local s = sw.knobGlow.Slot
                        if s then s:SetPosition(FVector2D(targetX - 3, baseY + knobPad - 3)) end
                    end)
                end
            end
        end
    end
    if sw.glow and IsValidUI(sw.glow) then
        local target = checked and 0.75 or 0.10
        if animate then
            local start = sw._glowAlpha or target
            sw._glowAlpha = target
            pcall(function()
                _G.U5Tween(0.20, start, target, function(v)
                    if sw.glow and IsValidUI(sw.glow) then
                        sw.glow:SetBrushColor(AccentColor(sw.tab, v))
                    end
                end)
            end)
        else
            sw._glowAlpha = target
            pcall(function() sw.glow:SetBrushColor(AccentColor(sw.tab, target)) end)
        end
    end
end

-- ---------- Toggle 行 ----------
local function MakeToggleRow(parent, label, x, y, w, configKey, cfgTable, saveName, tabIdx)
    tabIdx = tabIdx or currentParentTab
    _G.U5Defaults[saveName] = _G.U5Defaults[saveName] or {}
    if _G.U5Defaults[saveName][configKey] == nil then
        _G.U5Defaults[saveName][configKey] = cfgTable[configKey]
    end

    local h = 34
    local yOff = (CELL_H - h) * 0.5 - 3
    local rowY = y + yOff

    local bg      = Layer(parent, x, rowY, w, h, C.bg_row, 100)
    local accent  = Layer(parent, x, rowY, 3, h, AccentColor(tabIdx, 0.85), 103)
    local hover   = Layer(parent, x, rowY, w, h, C.bg_row_hover, 101)
    pcall(function() hover:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
    local sweep   = Layer(parent, x, rowY, 60, h, AccentDeep(tabIdx, 0.22), 102)
    pcall(function() sweep:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
    MakeCorners(parent, x, rowY, w, h, AccentColor(tabIdx, 0.55), 105, 6, 1)

    local state = cfgTable[configKey] == 1
    local swX = x + w - 34 - 12
    local swY = rowY + h * 0.5 - 9
    local sw = MakeSwitch(parent, swX, swY, state, tabIdx)
    local labelText = Text(parent, label, x + 14, rowY + h * 0.5, 11,
        C.text_normal, 300, 0, 0.5)

    local row = {
        kind = "toggle", label = label, configKey = configKey,
        cfgTable = cfgTable, saveName = saveName,
        parentIdx = currentParentTab, subIdx = currentSubTab[currentParentTab],
        refresh = function() SetSwitch(sw, cfgTable[configKey] == 1) end,
        setVisible = function(vis)
            local sv = vis and UEnums.ESlateVisibility.SelfHitTestInvisible
                            or  UEnums.ESlateVisibility.Collapsed
            for _, ww in ipairs({bg, accent, labelText, hover, sweep}) do
                if ww and IsValidUI(ww) then
                    pcall(function() ww:SetWidgetVisibility(sv) end)
                end
            end
            if sw then
                for _, k in ipairs({"bg","glow","border","knob","inner","knobGlow"}) do
                    if IsValidUI(sw[k]) then
                        pcall(function() sw[k]:SetWidgetVisibility(sv) end)
                    end
                end
            end
        end,
    }
    _G.U5RegisterRow(currentParentTab, currentSubTab[currentParentTab], row)

    MakeBtn(parent, x, rowY, w, h, 900,
        function()
            local newState = not (cfgTable[configKey] == 1)
            cfgTable[configKey] = newState and 1 or 0
            if _G.ConfigAutoSave then
                _G.ConfigAutoSave:MarkDirty(saveName)
            end
            SetSwitch(sw, newState, true)
            pcall(function()
                accent:SetBrushColor(AccentDeep(tabIdx, 1.0))
                _G.U5Tween(0.25, 1.0, 0.85, function(v)
                    pcall(function()
                        accent:SetBrushColor(AccentColor(tabIdx, v))
                    end)
                end)
            end)
        end,
        function()
            pcall(function()
                hover:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                sweep:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                local startX = x + w
                local endX = x - 60
                _G.U5Tween(0.55, startX, endX, function(v)
                    if sweep and IsValidUI(sweep) then
                        local s = sweep.Slot
                        if s then s:SetPosition(FVector2D(v, rowY)) end
                    end
                end)
            end)
        end,
        function()
            pcall(function()
                hover:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                sweep:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
            end)
        end
    )

    return row
end

-- ---------- 双击输入编辑器 ----------
local function _ShowValueEditor(parent, cx, cy, initText, onCommit)
    local edit = nil
    pcall(function()
        edit = CGame:NewObjectFromPath("/Script/UMG.EditableTextBox", parent)
    end)
    if not edit or not slua.isValid(edit) then return end
    pcall(function()
        edit:SetText(tostring(initText))
        edit:SetWidgetVisibility(UEnums.ESlateVisibility.Visible)
        local slot = parent:AddChildToCanvas(edit)
        if slot then
            slot:SetAutoSize(false)
            slot:SetPosition(FVector2D(cx - 35, cy - 11))
            slot:SetSize(FVector2D(70, 22))
            slot:SetZOrder(3000)
        end
        if edit.OnTextCommitted then
            edit.OnTextCommitted:Add(function(text)
                pcall(function()
                    onCommit(tostring(text))
                    edit:RemoveFromParent()
                    edit:ConditionalBeginDestroy()
                end)
            end)
        end
    end)
end

-- ---------- Slider 行 ----------
local function MakeSliderRow(parent, label, x, y, w, configKey, min, max, step,
                             cfgTable, saveName, tabIdx)
    tabIdx = tabIdx or currentParentTab
    _G.U5Defaults[saveName] = _G.U5Defaults[saveName] or {}
    if _G.U5Defaults[saveName][configKey] == nil then
        _G.U5Defaults[saveName][configKey] = cfgTable[configKey]
    end

    local v = cfgTable[configKey]
    if type(v) ~= "number" then v = min end
    v = math.max(min, math.min(max, v))
    local function fmt(val)
        if step < 0.01 then return string.format("%.3f", val) end
        if step < 1 then return string.format("%.2f", val) end
        return tostring(math.floor(val + 0.5))
    end
    local function pct(val) return (val - min) / (max - min) end

    local h = 36
    local yOff = (CELL_H - h) * 0.5 - 3
    local rowY = y + yOff

    local bg      = Layer(parent, x, rowY, w, h, C.bg_row, 100)
    local accent  = Layer(parent, x, rowY, 3, h, AccentColor(tabIdx, 0.85), 103)
    local hover   = Layer(parent, x, rowY, w, h, C.bg_row_hover, 101)
    pcall(function() hover:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
    MakeCorners(parent, x, rowY, w, h, AccentColor(tabIdx, 0.55), 105, 6, 1)

    local labelText = Text(parent, label, x + 14, rowY + h * 0.5, 11,
        C.text_normal, 300, 0, 0.5)

    -- 数值显示：放在滑块前面（左侧）
    local valX = x + w - 210
    local valText = Text(parent, fmt(v), valX, rowY + h * 0.5, 12,
        AccentDeep(tabIdx), 700, 0.5, 0.5, true, true)

    local btnW, btnH = 20, h - 12
    local btnY = rowY + 6
    local minusX = x + w - 24 - btnW - 4
    local plusX  = x + w - 24

    Layer(parent, minusX+1, btnY+1, btnW, btnH, C.shadow_deep, 501)
    Layer(parent, minusX, btnY, btnW, btnH, AccentDim(tabIdx, 1.0), 502)
    MakeCorners(parent, minusX, btnY, btnW, btnH, AccentColor(tabIdx, 0.9), 504, 4, 1)
    Text(parent, "−", minusX + btnW*0.5, rowY + h*0.5, 15,
        C.text_bright, 503, 0.5, 0.5, true, true)

    Layer(parent, plusX+1, btnY+1, btnW, btnH, C.shadow_deep, 501)
    Layer(parent, plusX, btnY, btnW, btnH, AccentDim(tabIdx, 1.0), 502)
    MakeCorners(parent, plusX, btnY, btnW, btnH, AccentColor(tabIdx, 0.9), 504, 4, 1)
    Text(parent, "+", plusX + btnW*0.5, rowY + h*0.5, 15,
        C.text_bright, 503, 0.5, 0.5, true, true)

    -- 独立编辑按钮（位于滑块与 +/- 之间）
    local editW = 22
    local editX = minusX - editW - 6
    local editShadow = Layer(parent, editX+1, btnY+1, editW, btnH, C.shadow_deep, 501)
    local editBg = Layer(parent, editX, btnY, editW, btnH, AccentDim(tabIdx, 1.0), 502)
    local editCorner = MakeCorners(parent, editX, btnY, editW, btnH, AccentColor(tabIdx, 0.9), 504, 4, 1)
    local editLabel = Text(parent, "✎", editX + editW*0.5, rowY + h*0.5, 13,
        C.text_bright, 503, 0.5, 0.5, true, true)

    -- 滑块放在数值显示之后
    local barW = 96
    local barX = editX - barW - 12
    local barY = rowY + h * 0.5 - 3
    Layer(parent, barX, barY, barW, 6, C.bg_input, 110)
    local fillGlow = Layer(parent, barX, barY-2, math.max(2, barW * pct(v)), 10,
        AccentColor(tabIdx, 0.25), 110)
    local fill = Layer(parent, barX, barY, math.max(2, barW * pct(v)), 6,
        AccentColor(tabIdx, 0.95), 111)
    local hx = barX + math.max(2, barW * pct(v)) - 6
    local handleGlow = Layer(parent, hx-3, barY-7, 18, 20,
        AccentDeep(tabIdx, 0.55), 111)
    local handle = Layer(parent, hx, barY - 4, 12, 14,
        AccentDeep(tabIdx, 1.0), 113)

    local colorPreview, colorPreviewUpd
    do
        local prefix = configKey:match("^(.-)_R$")
        if prefix and cfgTable[prefix.."_G"] ~= nil and
           cfgTable[prefix.."_B"] ~= nil then
            local px = x + w - 240
            local py = rowY + h * 0.5 - 5
            Layer(parent, px-1, py-1, 12, 12, C.border, 704)
            colorPreview = Layer(parent, px, py, 10, 10, C.bg_input, 705)
            colorPreviewUpd = function()
                local r = (cfgTable[prefix.."_R"] or 0)/255
                local g = (cfgTable[prefix.."_G"] or 0)/255
                local b = (cfgTable[prefix.."_B"] or 0)/255
                pcall(function()
                    colorPreview:SetBrushColor(FLinearColor(r,g,b,1))
                end)
            end
            colorPreviewUpd()
        end
    end

    local function refresh()
        local cur = cfgTable[configKey] or min
        if IsValidUI(valText) then valText:SetText(fmt(cur)) end
        local p = pct(cur)
        local newW = math.max(2, barW*p)
        if IsValidUI(fill) then
            local s = fill.Slot
            if s then s:SetSize(FVector2D(newW, 6)) end
        end
        if IsValidUI(fillGlow) then
            local s = fillGlow.Slot
            if s then s:SetSize(FVector2D(newW, 10)) end
        end
        if IsValidUI(handle) then
            local s = handle.Slot
            if s then s:SetPosition(FVector2D(barX + newW - 6, barY - 4)) end
        end
        if IsValidUI(handleGlow) then
            local s = handleGlow.Slot
            if s then s:SetPosition(FVector2D(barX + newW - 9, barY - 7)) end
        end
        if colorPreviewUpd then pcall(colorPreviewUpd) end
    end

    local row = {
        kind = "slider", label = label, configKey = configKey,
        cfgTable = cfgTable, saveName = saveName,
        parentIdx = currentParentTab, subIdx = currentSubTab[currentParentTab],
        refresh = refresh,
        setVisible = function(vis)
            local sv = vis and UEnums.ESlateVisibility.SelfHitTestInvisible
                            or  UEnums.ESlateVisibility.Collapsed
            for _, ww in ipairs({bg, accent, labelText, colorPreview,
                                  fill, fillGlow, handle, handleGlow, valText,
                                  editShadow, editBg, editCorner, editLabel}) do
                if ww and IsValidUI(ww) then
                    pcall(function() ww:SetWidgetVisibility(sv) end)
                end
            end
        end,
    }
    _G.U5RegisterRow(currentParentTab, currentSubTab[currentParentTab], row)

    local onHover = function()
        pcall(function()
            hover:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)
    end
    local onUnhover = function()
        pcall(function()
            hover:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
        end)
    end

    MakeBtn(parent, minusX, btnY, btnW, btnH, 900, function()
        local cur = cfgTable[configKey] or min
        cur = math.floor((cur - step) / step + 0.5) * step
        if cur < min then cur = min end
        cfgTable[configKey] = cur
        if _G.ConfigAutoSave then _G.ConfigAutoSave:MarkDirty(saveName) end
        refresh()
    end, onHover, onUnhover)

    MakeBtn(parent, plusX, btnY, btnW, btnH, 900, function()
        local cur = cfgTable[configKey] or min
        cur = math.floor((cur + step) / step + 0.5) * step
        if cur > max then cur = max end
        cfgTable[configKey] = cur
        if _G.ConfigAutoSave then _G.ConfigAutoSave:MarkDirty(saveName) end
        refresh()
    end, onHover, onUnhover)

    -- 独立编辑按钮：始终打开数值编辑框
    MakeBtn(parent, editX, btnY, editW, btnH, 900, function()
        _ShowValueEditor(parent, editX + editW * 0.5, rowY + h * 0.5,
            fmt(cfgTable[configKey]),
            function(text)
                local nv = tonumber(text)
                if not nv then return end
                nv = math.max(min, math.min(max, nv))
                cfgTable[configKey] = nv
                if _G.ConfigAutoSave then
                    _G.ConfigAutoSave:MarkDirty(saveName)
                end
                refresh()
            end)
    end, onHover, onUnhover)

    -- 数值区域：双击也可打开编辑框（保留原有习惯）
    MakeBtn(parent, valX - 24, rowY + 6, 48, h - 12, 720, function()
        local now = os.clock()
        if now - _G.U5UIState.lastValClick < 0.4 then
            _G.U5UIState.lastValClick = 0
            _ShowValueEditor(parent, valX, rowY + h * 0.5,
                fmt(cfgTable[configKey]),
                function(text)
                    local nv = tonumber(text)
                    if not nv then return end
                    nv = math.max(min, math.min(max, nv))
                    cfgTable[configKey] = nv
                    if _G.ConfigAutoSave then
                        _G.ConfigAutoSave:MarkDirty(saveName)
                    end
                    refresh()
                end)
        else
            _G.U5UIState.lastValClick = now
        end
    end, onHover, onUnhover)

    return row
end

-- ---------- Section 标题 ----------
local function MakeSectionLabel(parent, label, x, y, w, tabIdx)
    tabIdx = tabIdx or currentParentTab
    local h = 28
    local yOff = (CELL_H - h) * 0.5 - 3
    local rowY = y + yOff

    Layer(parent, x, rowY, w, h, C.bg_header, 90)
    Layer(parent, x, rowY, 4, h, AccentColor(tabIdx, 1.0), 92)
    MakeGradientBar(parent, x + 4, rowY + h - 2, w - 4, 2,
        AccentColor(tabIdx, 0.75), 92, true)
    local diamond = Layer(parent, x + 18, rowY + h*0.5 - 3, 6, 6,
        AccentDeep(tabIdx, 1.0), 94, false, true, tabIdx)
    Text(parent, label, x + 32, rowY + h * 0.5, 11,
        AccentColor(tabIdx, 1.0), 95, 0, 0.5)

    if diamond and IsValidUI(diamond) then
        table.insert(pulseWidgets, {
            widget = diamond,
            base = AccentDeep(tabIdx, 1.0),
            tab = tabIdx,
            phase = math.random() * 6.28
        })
    end
end

-- ---------- 切换标签 ----------
SwitchSubTab = function(idx)
    currentSubTab[currentParentTab] = idx
    local pIdx = currentParentTab
    for i, tb in ipairs(subTabButtons[pIdx]) do
        if tb then
            if tb.bg and IsValidUI(tb.bg) then
                tb.bg:SetBrushColor(i == idx and AccentDim(pIdx, 0.55) or C.bg_header)
            end
            if tb.txt and IsValidUI(tb.txt) then
                local col = i == idx and C.text_bright or C.text_dim
                if FSlateColor then tb.txt:SetColorAndOpacity(FSlateColor(col))
                else tb.txt:SetColorAndOpacity(col) end
            end
            if tb.underline and IsValidUI(tb.underline) then
                tb.underline:SetWidgetVisibility(i == idx and
                    UEnums.ESlateVisibility.SelfHitTestInvisible
                    or UEnums.ESlateVisibility.Collapsed)
            end
        end
    end
    for i, sb in ipairs(subTabScrollBoxes[pIdx]) do
        if sb and IsValidUI(sb) then
            sb:SetWidgetVisibility(i == idx and
                UEnums.ESlateVisibility.Visible or UEnums.ESlateVisibility.Collapsed)
        end
    end
end

SwitchParentTab = function(idx)
    currentParentTab = idx
    for i, btn in ipairs(parentTabButtons) do
        if btn then
            local active = (i == idx)
            if btn.bg and IsValidUI(btn.bg) then
                btn.bg:SetBrushColor(active and AccentDim(i, 0.65) or C.bg_side)
            end
            if btn.bar and IsValidUI(btn.bar) then
                btn.bar:SetWidgetVisibility(active and
                    UEnums.ESlateVisibility.SelfHitTestInvisible
                    or UEnums.ESlateVisibility.Collapsed)
            end
            if btn.underGlow and IsValidUI(btn.underGlow) then
                btn.underGlow:SetWidgetVisibility(active and
                    UEnums.ESlateVisibility.SelfHitTestInvisible
                    or UEnums.ESlateVisibility.Collapsed)
            end
            if btn.glow and IsValidUI(btn.glow) then
                btn.glow:SetBrushColor(AccentColor(i, active and 0.35 or 0.0))
            end
            if btn.icon and IsValidUI(btn.icon) then
                local col = active and AccentDeep(i) or C.text_muted
                if FSlateColor then btn.icon:SetColorAndOpacity(FSlateColor(col))
                else btn.icon:SetColorAndOpacity(col) end
            end
            if btn.txt and IsValidUI(btn.txt) then
                local col = active and C.text_bright or C.text_dim
                if FSlateColor then btn.txt:SetColorAndOpacity(FSlateColor(col))
                else btn.txt:SetColorAndOpacity(col) end
            end
        end
    end
    for pIdx = 1, NUM_PARENT_TABS do
        local show = (pIdx == idx)
        local visShow = show and UEnums.ESlateVisibility.SelfHitTestInvisible
                              or  UEnums.ESlateVisibility.Collapsed
        local btnShow = show and UEnums.ESlateVisibility.Visible
                              or  UEnums.ESlateVisibility.Collapsed
        for _, tb in ipairs(subTabButtons[pIdx]) do
            if tb then
                if tb.bg and IsValidUI(tb.bg) then tb.bg:SetWidgetVisibility(visShow) end
                if tb.txt and IsValidUI(tb.txt) then tb.txt:SetWidgetVisibility(visShow) end
                if tb.underline and IsValidUI(tb.underline) then
                    tb.underline:SetWidgetVisibility(visShow)
                end
                if tb.btn and IsValidUI(tb.btn) then
                    tb.btn:SetWidgetVisibility(btnShow)
                end
            end
        end
        for _, sb in ipairs(subTabScrollBoxes[pIdx]) do
            if sb and IsValidUI(sb) then
                sb:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
            end
        end
    end
    SwitchSubTab(currentSubTab[idx])
end

-- ---------- 搜索 ----------
function _G.ApplySearchFilter()
    local kw = _G.U5UIState.searchKeyword or ""
    for _, subs in pairs(_G.U5Rows) do
        for _, rows in pairs(subs) do
            for _, row in ipairs(rows) do
                local match = (kw == "")
                if not match and row.label then
                    match = string.find(string.lower(row.label), kw, 1, true) ~= nil
                end
                if row.setVisible then pcall(row.setVisible, match) end
            end
        end
    end
end

-- ---------- 拖拽 ----------
function _G.U5UpdateDrag()
    local state = _G.U5UIState
    if not state.dragActive then
        state.dragMouseStart = nil
        return
    end
    local WLL = import("WidgetLayoutLibrary")
    if not WLL or not WLL.GetMousePositionOnViewport then return end
    local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
    if not (pc and slua.isValid(pc)) then return end
    local pos = nil
    pcall(function() pos = WLL.GetMousePositionOnViewport(pc) end)
    if not pos then return end
    if not state.dragMouseStart then
        state.dragMouseStart = { X = pos.X, Y = pos.Y }
        state.dragMenuStart  = { X = menuX, Y = menuY }
        return
    end
    local dx = (pos.X - state.dragMouseStart.X) / 2
    local dy = (pos.Y - state.dragMouseStart.Y) / 2
    menuX = math.max(0, math.min(2600, state.dragMenuStart.X + dx))
    menuY = math.max(0, math.min(1600, state.dragMenuStart.Y + dy))
    if bgPanel and IsValidUI(bgPanel) then
        local s = bgPanel.Slot
        if s then
            pcall(function() s:SetPosition(FVector2D(menuX, menuY)) end)
        end
    end
end

-- ---------- 性能 ----------
_G.U5Perf = _G.U5Perf or { last = os.clock(), frames = 0, fps = 0 }
function _G.U5UpdatePerf()
    local p = _G.U5Perf
    p.frames = p.frames + 1
    local now = os.clock()
    if now - p.last >= 1.0 then
        p.fps = p.frames
        p.frames = 0
        p.last = now
        if _G._U5_PerfText and IsValidUI(_G._U5_PerfText) then
            local rows = 0
            for _, subs in pairs(_G.U5Rows or {}) do
                for _, rs in pairs(subs) do rows = rows + #rs end
            end
            pcall(function()
                _G._U5_PerfText:SetText("FPS " .. p.fps .. " | Rows " .. rows)
            end)
        end
    end
end

-- ---------- 语言 ----------
function _G.U5SetLanguage(lang)
    _G.U5UIState.lang = lang or "zh"
    if bgPanel and IsValidUI(bgPanel) then
        pcall(function()
            bgPanel:RemoveFromParent()
            bgPanel:ConditionalBeginDestroy()
        end)
    end
    bgPanel = nil
    menuBuilt = false
    if isMenuOpen and BuildMenu then BuildMenu() end
end

-- ============================================================
-- 菜单过渡动画（新增）
-- ============================================================
local function _SetMenuVisible(trueVisible)
    if not bgPanel or not IsValidUI(bgPanel) then return end
    pcall(function()
        if trueVisible then
            bgPanel:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        else
            bgPanel:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
        end
    end)
end

local function _SetMenuOpacity(v)
    if not bgPanel or not IsValidUI(bgPanel) then return end
    pcall(function()
        bgPanel:SetRenderOpacity(v)
    end)
end

local function _SetMenuPosition(x, y)
    if not bgPanel or not IsValidUI(bgPanel) then return end
    pcall(function()
        local s = bgPanel.Slot
        if s then s:SetPosition(FVector2D(x, y)) end
    end)
end

function _G.U5AnimateMenuOpen()
    if not bgPanel or not IsValidUI(bgPanel) then return end
    if _G.U5UIState.animating then return end
    _G.U5UIState.animating = true
    _G.U5UIState.dragActive = false

    -- 起始状态：透明 + 从右上偏移 36px
    local startX = menuX + 36
    local startY = menuY - 24
    _SetMenuVisible(true)
    _SetMenuOpacity(0.0)
    _SetMenuPosition(startX, startY)

    _G.U5Tween(0.28, 0, 1, function(v)
        _SetMenuOpacity(v)
        _SetMenuPosition(
            startX + (menuX - startX) * v,
            startY + (menuY - startY) * v
        )
    end, function()
        _SetMenuOpacity(1.0)
        _SetMenuPosition(menuX, menuY)
        _G.U5UIState.animating = false
    end)
end

function _G.U5AnimateMenuClose(onDone)
    if not bgPanel or not IsValidUI(bgPanel) then
        if onDone then pcall(onDone) end
        return
    end
    if _G.U5UIState.animating then
        -- 打断当前动画，直接走关闭
        _G.U5UIState.animating = false
    end
    _G.U5UIState.animating = true
    _G.U5UIState.dragActive = false

    local startX = menuX
    local startY = menuY
    local endX = menuX + 36
    local endY = menuY - 24

    _G.U5Tween(0.20, 0, 1, function(v)
        _SetMenuOpacity(1 - v)
        _SetMenuPosition(
            startX + (endX - startX) * v,
            startY + (endY - startY) * v
        )
    end, function()
        _SetMenuOpacity(1.0)          -- 复位，下次打开时不影响
        _SetMenuPosition(menuX, menuY) -- 复位位置
        _SetMenuVisible(false)
        _G.U5UIState.animating = false
        if onDone then pcall(onDone) end
    end)
end

-- ============================================================
-- v5.4 毛玻璃双面板 + 插画背景数据（由 image_download_1790280726015.jpg 生成）
-- 格式 {y,x,w,h,idx}: idx>=1 = 插画调色板(64色: 右1-32 / 左33-64); 500 = 面板底色(毛玻璃白)
-- 设计基准: M_W=1267, M_H=799; 左面板 316x799 @(0,0); 右面板 921x799 @(346,0)
-- ============================================================
_G.U5ArtDesign = { W = 1267, H = 799, LW = 316, RW = 921 }
_G.U5ArtPal = {
    {1.000,1.000,1.000},
    {1.000,0.996,1.000},
    {0.996,0.996,1.000},
    {0.996,0.996,0.996},
    {0.996,0.996,0.988},
    {1.000,0.988,0.996},
    {0.992,0.992,0.992},
    {1.000,0.976,0.996},
    {1.000,0.976,0.992},
    {0.996,0.965,0.992},
    {0.992,0.969,0.992},
    {0.976,0.965,0.988},
    {0.984,0.953,0.984},
    {0.980,0.941,0.980},
    {0.961,0.945,0.976},
    {0.941,0.941,0.984},
    {0.957,0.922,0.969},
    {0.925,0.918,0.969},
    {0.933,0.902,0.953},
    {0.929,0.878,0.925},
    {0.894,0.898,0.961},
    {0.882,0.882,0.957},
    {0.882,0.867,0.922},
    {0.847,0.863,0.961},
    {0.871,0.843,0.902},
    {0.871,0.812,0.867},
    {0.820,0.827,0.918},
    {0.796,0.788,0.863},
    {0.796,0.753,0.816},
    {0.729,0.729,0.816},
    {0.694,0.667,0.741},
    {0.576,0.427,0.490},
    {1.000,1.000,1.000},
    {0.996,1.000,0.996},
    {1.000,0.996,1.000},
    {0.996,0.996,0.996},
    {0.996,0.996,0.992},
    {0.988,0.996,0.996},
    {1.000,0.992,0.996},
    {1.000,0.984,0.996},
    {0.988,0.988,0.992},
    {1.000,0.976,0.996},
    {0.992,0.973,0.992},
    {0.996,0.969,0.992},
    {0.992,0.957,0.992},
    {0.980,0.965,0.992},
    {0.980,0.953,0.984},
    {0.965,0.957,0.984},
    {0.969,0.941,0.976},
    {0.957,0.925,0.969},
    {0.933,0.933,0.976},
    {0.933,0.918,0.965},
    {0.941,0.902,0.953},
    {0.918,0.898,0.945},
    {0.898,0.898,0.957},
    {0.890,0.878,0.937},
    {0.882,0.863,0.925},
    {0.882,0.835,0.902},
    {0.839,0.839,0.914},
    {0.820,0.812,0.890},
    {0.792,0.776,0.851},
    {0.741,0.745,0.824},
    {0.698,0.690,0.773},
    {0.612,0.514,0.592},
}
_G.U5ArtL = {
{0,30,256,1,500},
{1,22,272,1,500},
{2,19,278,1,500},
{3,17,282,1,500},
{4,15,286,1,500},
{5,13,290,1,500},
{6,12,292,1,500},
{7,11,294,1,500},
{8,10,296,1,500},
{9,9,298,1,500},
{10,8,300,1,500},
{11,7,302,1,500},
{12,6,304,1,500},
{13,5,306,2,500},
{15,4,308,1,500},
{16,3,310,3,500},
{19,2,312,2,500},
{21,1,314,4,500},
{25,0,316,749,500},
{774,1,314,4,500},
{778,2,312,2,500},
{780,3,310,3,500},
{783,4,308,1,500},
{784,5,306,2,500},
{786,6,304,1,500},
{787,7,302,1,500},
{788,8,300,1,500},
{789,9,298,1,500},
{790,10,296,1,500},
{791,11,294,1,500},
{792,12,292,1,500},
{793,13,290,1,500},
{794,15,286,1,500},
{795,17,282,1,500},
{796,19,278,1,500},
{797,22,272,1,500},
{798,30,256,1,500},
{0,13,27,13,36},
{0,40,13,13,33},
{0,53,13,13,50},
{0,79,13,13,50},
{0,92,13,13,45},
{0,105,27,13,44},
{0,132,26,13,42},
{0,198,13,13,56},
{0,224,13,13,41},
{0,250,13,13,47},
{0,263,13,13,33},
{0,276,27,13,36},
{0,66,13,26,46},
{0,158,13,26,53},
{0,184,14,26,50},
{0,211,13,26,33},
{0,237,13,26,57},
{13,26,14,13,34},
{13,40,13,13,41},
{13,79,13,13,54},
{13,92,26,13,42},
{13,118,27,13,44},
{13,145,13,13,42},
{13,198,13,13,57},
{13,224,13,13,39},
{13,250,13,13,49},
{13,263,13,13,39},
{13,276,14,13,36},
{13,290,13,13,39},
{13,303,13,13,40},
{13,0,26,26,36},
{13,53,13,26,49},
{26,40,13,13,48},
{26,66,13,13,48},
{26,79,13,13,53},
{26,92,13,13,39},
{26,105,13,13,43},
{26,118,14,13,44},
{26,132,13,13,46},
{26,145,13,13,40},
{26,158,13,13,50},
{26,211,26,13,33},
{26,237,13,13,54},
{26,250,13,13,50},
{26,263,13,13,49},
{26,276,14,13,33},
{0,171,13,52,46},
{26,26,14,26,33},
{26,184,14,26,53},
{26,290,13,26,40},
{26,303,13,26,42},
{39,0,13,13,36},
{39,13,13,13,38},
{39,53,13,13,50},
{39,66,13,13,47},
{39,79,13,13,49},
{39,92,13,13,38},
{39,105,13,13,40},
{39,118,27,13,47},
{39,145,13,13,35},
{39,158,13,13,47},
{39,211,13,13,35},
{39,224,13,13,33},
{39,237,26,13,50},
{39,276,14,13,39},
{39,40,13,26,54},
{39,263,13,26,53},
{52,0,26,13,36},
{52,26,14,13,35},
{52,66,13,13,46},
{52,79,13,13,44},
{52,92,13,13,46},
{52,105,13,13,43},
{52,118,14,13,44},
{52,145,13,13,33},
{52,158,13,13,43},
{52,211,13,13,42},
{52,224,13,13,40},
{52,237,13,13,46},
{52,276,14,13,45},
{52,53,13,27,48},
{52,184,14,27,52},
{52,250,13,27,49},
{52,290,26,27,42},
{65,13,13,14,34},
{65,26,14,14,40},
{65,40,13,14,56},
{65,66,13,14,45},
{65,92,13,14,50},
{65,105,13,14,48},
{65,118,14,14,40},
{65,145,13,14,36},
{65,211,13,14,45},
{65,224,13,14,39},
{65,237,13,14,43},
{65,263,27,14,50},
{26,198,13,66,58},
{52,171,13,40,47},
{65,0,13,27,36},
{79,26,14,13,46},
{79,66,13,13,47},
{79,92,13,13,53},
{79,105,13,13,50},
{79,118,14,13,35},
{79,145,13,13,41},
{79,211,13,13,50},
{79,224,13,13,40},
{79,250,13,13,47},
{79,263,13,13,49},
{79,290,13,13,46},
{79,303,13,13,45},
{52,132,13,53,49},
{65,158,13,40,40},
{79,184,14,26,50},
{79,237,13,26,42},
{79,276,14,26,54},
{92,0,13,13,39},
{92,26,14,13,49},
{92,66,13,13,49},
{92,92,13,13,50},
{92,105,13,13,52},
{92,118,14,13,39},
{92,145,13,13,46},
{92,171,13,13,44},
{92,224,13,13,44},
{92,250,13,13,46},
{92,263,13,13,44},
{92,290,13,13,50},
{92,303,13,13,47},
{65,79,13,53,42},
{79,53,13,39,46},
{92,211,13,26,54},
{105,26,14,13,50},
{105,66,13,13,50},
{105,92,13,13,52},
{105,118,14,13,40},
{105,132,13,13,46},
{105,158,26,13,42},
{105,224,13,13,50},
{105,237,13,13,40},
{105,250,13,13,44},
{105,263,13,13,42},
{105,276,14,13,50},
{105,290,13,13,54},
{105,303,13,13,46},
{92,198,13,39,56},
{105,105,13,26,54},
{105,145,13,26,47},
{105,184,14,26,49},
{118,26,14,13,54},
{118,53,13,13,47},
{118,79,13,13,43},
{118,92,13,13,49},
{118,118,14,13,46},
{118,132,13,13,36},
{118,158,13,13,42},
{118,211,26,13,54},
{118,237,13,13,46},
{118,250,26,13,42},
{118,276,14,13,49},
{118,290,13,13,56},
{118,303,13,13,50},
{79,40,13,65,57},
{105,0,13,39,41},
{118,171,13,26,45},
{131,26,14,13,56},
{131,53,13,13,48},
{131,79,13,13,46},
{131,105,13,13,52},
{131,118,14,13,48},
{131,158,13,13,44},
{131,184,14,13,47},
{131,198,26,13,54},
{131,237,13,13,48},
{131,250,13,13,42},
{131,263,13,13,44},
{131,276,14,13,45},
{131,290,13,13,53},
{79,13,13,78,33},
{131,92,13,26,48},
{131,132,13,26,33},
{131,145,13,26,41},
{131,303,13,26,56},
{144,0,13,13,36},
{144,79,13,13,49},
{144,105,27,13,51},
{144,158,13,13,46},
{144,171,13,13,44},
{144,198,13,13,52},
{144,211,13,13,56},
{144,250,13,13,43},
{144,263,40,13,45},
{118,66,13,52,52},
{131,224,13,39,55},
{144,53,13,26,51},
{144,237,13,26,51},
{157,0,26,13,36},
{157,79,13,13,50},
{157,92,13,13,46},
{157,105,13,13,51},
{157,118,14,13,52},
{157,132,13,13,41},
{157,145,13,13,40},
{157,158,13,13,44},
{157,171,13,13,42},
{157,198,13,13,51},
{157,211,13,13,57},
{157,250,13,13,48},
{157,263,13,13,44},
{157,276,14,13,49},
{157,290,13,13,47},
{157,303,13,13,50},
{144,26,27,39,57},
{144,184,14,39,49},
{170,0,13,13,35},
{170,53,13,13,55},
{170,66,13,13,51},
{170,79,13,13,53},
{170,92,13,13,45},
{170,105,13,13,48},
{170,118,14,13,54},
{170,132,13,13,48},
{170,158,26,13,44},
{170,211,13,13,56},
{170,224,13,13,60},
{170,237,13,13,55},
{170,263,13,13,46},
{170,290,13,13,50},
{170,303,13,13,49},
{170,145,13,26,39},
{170,198,13,26,52},
{170,250,13,26,51},
{170,276,14,26,47},
{183,26,27,13,59},
{183,53,13,13,56},
{183,66,13,13,52},
{183,79,13,13,56},
{183,92,13,13,50},
{183,118,14,13,52},
{183,132,13,13,54},
{183,158,13,13,43},
{183,171,13,13,44},
{183,184,14,13,47},
{183,211,13,13,51},
{183,224,26,13,60},
{183,263,13,13,48},
{183,290,13,13,53},
{183,303,13,13,54},
{170,13,13,40,41},
{183,105,13,27,42},
{196,26,27,14,60},
{196,66,26,14,56},
{196,92,13,14,57},
{196,118,14,14,49},
{196,132,13,14,56},
{196,145,13,14,45},
{196,171,13,14,43},
{196,184,14,14,45},
{196,198,13,14,51},
{196,211,13,14,55},
{196,224,13,14,56},
{196,250,13,14,57},
{196,263,13,14,54},
{196,290,13,14,49},
{196,303,13,14,57},
{196,53,13,27,59},
{196,158,13,27,40},
{196,237,13,27,63},
{196,276,14,27,50},
{210,26,14,13,60},
{210,40,13,13,61},
{210,66,26,13,57},
{210,92,13,13,61},
{210,105,13,13,56},
{210,118,14,13,40},
{210,132,13,13,54},
{210,145,13,13,52},
{210,171,13,13,44},
{210,198,13,13,50},
{210,211,13,13,54},
{210,224,13,13,51},
{210,250,13,13,62},
{210,263,13,13,51},
{210,290,13,13,45},
{210,303,13,13,50},
{210,13,13,26,48},
{223,26,14,13,59},
{223,40,13,13,62},
{223,53,26,13,60},
{223,79,13,13,59},
{223,92,13,13,60},
{223,118,27,13,48},
{223,158,13,13,46},
{223,171,13,13,42},
{223,198,13,13,51},
{223,211,13,13,52},
{223,224,13,13,56},
{223,237,13,13,60},
{223,250,13,13,61},
{223,263,13,13,57},
{223,290,13,13,53},
{223,303,13,13,49},
{210,184,14,39,47},
{223,105,13,26,63},
{223,145,13,26,54},
{223,276,14,26,54},
{236,13,13,13,50},
{236,26,14,13,54},
{236,40,26,13,62},
{236,66,26,13,61},
{236,92,13,13,51},
{236,118,14,13,61},
{236,132,13,13,41},
{236,158,13,13,52},
{236,171,13,13,40},
{236,198,13,13,52},
{236,211,13,13,51},
{236,224,13,13,57},
{236,237,13,13,58},
{236,250,26,13,61},
{236,290,13,13,50},
{236,303,13,13,45},
{249,13,13,13,51},
{249,26,14,13,47},
{249,40,13,13,62},
{249,66,26,13,62},
{249,92,26,13,56},
{249,118,14,13,63},
{249,132,13,13,56},
{249,145,13,13,46},
{249,158,13,13,54},
{249,171,27,13,47},
{249,198,39,13,54},
{249,237,13,13,60},
{249,290,13,13,61},
{249,303,13,13,58},
{249,250,13,26,63},
{249,263,27,26,64},
{262,13,13,13,52},
{262,26,14,13,46},
{262,40,13,13,60},
{262,79,13,13,63},
{262,92,13,13,61},
{262,105,13,13,51},
{262,118,14,13,59},
{262,132,13,13,62},
{262,145,13,13,52},
{262,158,13,13,53},
{262,171,13,13,54},
{262,184,14,13,45},
{262,211,13,13,59},
{262,224,13,13,61},
{262,237,13,13,62},
{262,290,26,13,63},
{249,53,13,39,63},
{262,66,13,26,62},
{262,198,13,26,51},
{275,13,13,13,50},
{275,26,14,13,45},
{275,40,13,13,54},
{275,79,26,13,63},
{275,105,27,13,56},
{275,132,13,13,58},
{275,145,13,13,60},
{275,158,13,13,52},
{275,171,13,13,57},
{275,184,14,13,52},
{275,224,13,13,63},
{275,250,13,13,60},
{275,263,40,13,64},
{275,303,13,13,62},
{183,0,13,118,33},
{275,211,13,26,61},
{288,13,13,13,47},
{288,26,14,13,43},
{288,53,52,13,63},
{288,105,13,13,61},
{288,118,14,13,56},
{288,145,13,13,56},
{288,158,13,13,55},
{288,171,13,13,52},
{288,184,14,13,59},
{288,198,13,13,60},
{288,224,13,13,62},
{288,250,13,13,57},
{288,263,13,13,62},
{288,276,40,13,64},
{275,237,13,39,61},
{288,132,13,26,59},
{301,53,13,13,62},
{301,79,13,13,61},
{301,92,26,13,63},
{301,118,14,13,55},
{301,145,26,13,57},
{301,171,13,13,55},
{301,184,14,13,56},
{301,198,26,13,63},
{301,224,13,13,54},
{301,250,13,13,58},
{301,263,13,13,56},
{301,276,14,13,63},
{301,290,13,13,64},
{301,303,13,13,63},
{288,40,13,39,49},
{301,26,14,26,42},
{301,66,13,26,64},
{314,53,13,13,58},
{314,79,26,13,62},
{314,105,13,13,63},
{314,118,14,13,60},
{314,145,13,13,60},
{314,171,13,13,57},
{314,184,14,13,59},
{314,198,13,13,60},
{314,211,13,13,61},
{314,224,13,13,57},
{314,237,13,13,53},
{314,250,13,13,61},
{314,263,27,13,58},
{314,290,13,13,63},
{314,303,13,13,58},
{301,0,13,40,34},
{301,13,13,40,46},
{314,132,13,27,55},
{327,26,14,14,44},
{327,40,13,14,45},
{327,53,13,14,57},
{327,66,26,14,62},
{327,92,13,14,60},
{327,105,27,14,63},
{327,145,13,14,57},
{327,171,13,14,55},
{327,184,14,14,56},
{327,198,26,14,61},
{327,224,13,14,60},
{327,237,13,14,54},
{327,263,13,14,61},
{327,276,14,14,58},
{327,290,26,14,53},
{314,158,13,40,56},
{327,250,13,27,53},
{341,53,26,13,57},
{341,79,13,13,56},
{341,92,26,13,60},
{341,118,14,13,64},
{341,132,13,13,61},
{341,145,13,13,55},
{341,171,13,13,51},
{341,184,14,13,55},
{341,198,13,13,56},
{341,211,13,13,60},
{341,224,13,13,62},
{341,263,13,13,50},
{341,276,14,13,61},
{341,290,13,13,58},
{341,303,13,13,49},
{341,0,13,26,33},
{341,13,27,26,47},
{341,40,13,26,40},
{341,237,13,26,61},
{354,53,13,13,53},
{354,66,13,13,58},
{354,79,13,13,45},
{354,92,13,13,57},
{354,105,13,13,55},
{354,118,14,13,61},
{354,132,13,13,63},
{354,145,13,13,60},
{354,158,13,13,57},
{354,171,13,13,56},
{354,184,14,13,51},
{354,198,26,13,56},
{354,224,13,13,59},
{354,250,13,13,60},
{354,263,13,13,53},
{354,276,14,13,50},
{354,290,13,13,60},
{354,303,13,26,58},
{367,13,13,13,43},
{367,26,14,13,45},
{367,40,13,13,42},
{367,53,13,13,47},
{367,66,13,13,60},
{367,79,26,13,49},
{367,105,13,13,54},
{367,118,14,13,55},
{367,132,13,13,62},
{367,145,13,13,63},
{367,158,13,13,61},
{367,171,13,13,60},
{367,184,14,13,59},
{367,198,13,13,51},
{367,211,13,13,52},
{367,224,13,13,56},
{367,237,13,13,59},
{367,250,26,13,61},
{367,276,14,13,54},
{367,290,13,13,53},
{367,0,13,26,34},
{380,13,13,13,41},
{380,26,14,13,47},
{380,40,26,13,42},
{380,66,26,13,58},
{380,92,13,13,42},
{380,105,13,13,53},
{380,118,14,13,56},
{380,132,26,13,60},
{380,158,13,13,63},
{380,171,13,13,62},
{380,184,14,13,61},
{380,198,13,13,60},
{380,211,13,13,55},
{380,224,13,13,51},
{380,237,13,13,55},
{380,250,13,13,59},
{380,263,13,13,62},
{380,276,14,13,58},
{380,303,13,13,54},
{380,290,13,26,57},
{393,0,26,13,36},
{393,26,14,13,49},
{393,40,13,13,41},
{393,66,13,13,50},
{393,79,13,13,61},
{393,92,13,13,47},
{393,105,13,13,44},
{393,118,27,13,57},
{393,158,13,13,59},
{393,171,13,13,63},
{393,184,27,13,61},
{393,211,13,13,60},
{393,224,13,13,61},
{393,237,13,13,59},
{393,250,13,13,51},
{393,263,13,13,63},
{393,276,14,13,64},
{393,303,13,13,53},
{393,53,13,26,35},
{393,145,13,26,61},
{406,0,13,13,36},
{406,13,13,13,33},
{406,26,14,13,46},
{406,40,13,13,48},
{406,79,13,13,60},
{406,92,13,13,54},
{406,105,13,13,35},
{406,118,14,13,49},
{406,132,13,13,57},
{406,158,13,13,62},
{406,171,13,13,59},
{406,184,14,13,63},
{406,198,13,13,62},
{406,211,13,13,59},
{406,224,13,13,55},
{406,237,13,13,61},
{406,250,13,13,62},
{406,263,13,13,57},
{406,276,27,13,64},
{406,303,13,13,58},
{406,66,13,26,39},
{419,0,26,13,36},
{419,26,14,13,41},
{419,40,13,13,47},
{419,79,13,13,50},
{419,92,13,13,58},
{419,105,13,13,40},
{419,118,14,13,42},
{419,132,13,13,50},
{419,145,13,13,58},
{419,158,13,13,63},
{419,171,27,13,59},
{419,198,26,13,63},
{419,224,13,13,59},
{419,237,13,13,51},
{419,250,13,13,60},
{419,263,13,13,62},
{419,290,13,13,63},
{419,303,13,13,64},
{419,53,13,26,44},
{419,276,14,26,61},
{432,0,40,13,36},
{432,40,13,13,39},
{432,79,13,13,40},
{432,92,13,13,56},
{432,105,13,13,49},
{432,118,14,13,44},
{432,132,13,13,42},
{432,145,13,13,53},
{432,158,13,13,61},
{432,171,13,13,56},
{432,184,14,13,51},
{432,198,13,13,59},
{432,211,13,13,63},
{432,224,13,13,64},
{432,237,13,13,61},
{432,250,13,13,51},
{432,263,13,13,56},
{432,290,13,13,60},
{432,303,13,13,63},
{432,66,13,26,43},
{445,53,13,13,40},
{445,79,13,13,33},
{445,92,13,13,52},
{445,118,40,13,42},
{445,158,13,13,58},
{445,171,13,13,54},
{445,184,14,13,49},
{445,198,13,13,56},
{445,224,13,13,62},
{445,237,13,13,64},
{445,250,13,13,62},
{445,263,13,13,59},
{445,276,14,13,55},
{445,290,26,13,59},
{445,0,53,27,36},
{445,105,13,27,56},
{445,211,13,27,59},
{458,53,26,14,39},
{458,79,13,14,36},
{458,92,13,14,38},
{458,118,14,14,50},
{458,132,13,14,43},
{458,145,13,14,35},
{458,158,13,14,54},
{458,171,13,14,60},
{458,184,14,14,40},
{458,198,13,14,54},
{458,224,13,14,57},
{458,237,13,14,60},
{458,250,26,14,63},
{458,276,14,14,60},
{458,290,26,14,57},
{472,0,92,13,36},
{472,92,13,13,33},
{472,105,13,13,43},
{472,118,14,13,53},
{472,145,13,13,40},
{472,158,13,13,46},
{472,171,13,13,58},
{472,184,14,13,50},
{472,198,13,13,43},
{472,211,26,13,58},
{472,237,13,13,51},
{472,250,13,13,55},
{472,263,13,13,63},
{472,276,14,13,64},
{472,290,13,13,63},
{472,303,13,13,59},
{472,132,13,26,45},
{485,0,105,13,36},
{485,105,13,13,34},
{485,118,14,13,40},
{485,145,13,13,44},
{485,158,13,13,39},
{485,171,13,13,53},
{485,184,14,13,57},
{485,198,13,13,39},
{485,211,13,13,43},
{485,224,13,13,58},
{485,237,13,13,57},
{485,250,13,13,42},
{485,263,13,13,54},
{485,276,40,13,63},
{498,0,118,13,36},
{498,118,14,13,39},
{498,132,26,13,42},
{498,158,13,13,35},
{498,171,13,13,33},
{498,184,14,13,56},
{498,198,13,13,49},
{498,211,13,13,35},
{498,224,13,13,41},
{498,237,13,13,58},
{498,250,13,13,50},
{498,263,13,13,42},
{498,276,14,13,54},
{498,290,26,13,63},
{511,66,39,13,36},
{511,105,27,13,33},
{511,132,13,13,39},
{511,158,13,13,53},
{511,171,40,13,47},
{511,211,26,13,33},
{511,237,13,13,43},
{511,250,13,13,54},
{511,263,13,13,44},
{511,276,14,13,42},
{511,290,13,13,56},
{511,303,13,13,63},
{511,40,13,26,40},
{511,145,13,26,49},
{524,79,13,13,37},
{524,92,13,13,33},
{524,105,13,13,48},
{524,132,13,13,48},
{524,158,13,13,54},
{524,171,13,13,53},
{524,184,14,13,54},
{524,198,13,13,58},
{524,211,13,13,50},
{524,224,13,13,41},
{524,237,13,13,35},
{524,250,13,13,46},
{524,263,13,13,40},
{524,276,27,13,39},
{524,303,13,13,57},
{511,0,13,39,36},
{511,13,27,39,37},
{511,53,13,39,37},
{524,66,13,26,36},
{524,118,14,26,52},
{537,40,13,13,39},
{537,79,13,13,33},
{537,92,13,13,50},
{537,105,13,13,54},
{537,132,13,13,46},
{537,145,13,13,40},
{537,158,13,13,39},
{537,171,13,13,40},
{537,184,14,13,44},
{537,198,13,13,54},
{537,211,26,13,58},
{537,237,26,13,57},
{537,263,27,13,58},
{537,290,13,13,60},
{537,303,13,13,61},
{550,0,66,13,36},
{550,66,13,13,33},
{550,79,13,13,48},
{550,92,13,13,54},
{550,105,13,13,51},
{550,118,14,13,46},
{550,132,13,13,47},
{550,145,13,13,44},
{550,158,26,13,40},
{550,184,14,13,42},
{550,198,13,13,39},
{550,211,13,13,47},
{550,224,13,13,54},
{550,237,13,13,51},
{550,250,13,13,52},
{550,263,13,13,62},
{550,276,14,13,63},
{550,290,13,13,59},
{550,303,13,13,56},
{563,0,40,13,36},
{563,40,13,13,41},
{563,53,13,13,33},
{563,66,13,13,52},
{563,79,13,13,54},
{563,92,13,13,50},
{563,105,13,13,48},
{563,118,14,13,44},
{563,132,13,13,45},
{563,145,13,13,42},
{563,171,13,13,36},
{563,184,14,13,44},
{563,198,13,13,40},
{563,211,13,13,42},
{563,224,13,13,47},
{563,237,13,13,46},
{563,250,26,13,48},
{563,276,14,13,57},
{563,290,13,13,61},
{563,303,13,13,48},
{563,158,13,26,39},
{576,0,53,13,36},
{576,53,13,13,38},
{576,66,13,13,60},
{576,79,13,13,48},
{576,92,13,13,47},
{576,105,27,13,44},
{576,132,13,13,42},
{576,145,13,13,40},
{576,184,14,13,49},
{576,198,13,13,43},
{576,211,26,13,39},
{576,237,13,13,41},
{576,250,13,13,33},
{576,263,13,13,48},
{576,276,14,13,51},
{576,290,13,13,60},
{576,303,13,13,62},
{576,171,13,27,33},
{589,0,26,14,36},
{589,26,14,14,38},
{589,53,13,14,52},
{589,66,13,14,58},
{589,79,13,14,39},
{589,92,26,14,45},
{589,118,27,14,42},
{589,145,13,14,35},
{589,158,13,14,36},
{589,184,27,14,49},
{589,211,13,14,33},
{589,224,13,14,37},
{589,237,26,14,36},
{589,263,13,14,33},
{589,276,14,14,48},
{589,290,13,14,52},
{589,303,13,14,60},
{589,40,13,27,33},
{603,0,40,13,36},
{603,53,13,13,60},
{603,66,13,13,53},
{603,79,13,13,40},
{603,92,13,13,44},
{603,118,14,13,46},
{603,132,13,13,42},
{603,145,13,13,39},
{603,158,26,13,36},
{603,184,14,13,43},
{603,198,13,13,53},
{603,211,13,13,44},
{603,224,26,13,40},
{603,250,26,13,36},
{603,276,14,13,39},
{603,290,13,13,43},
{603,303,13,13,52},
{603,105,13,26,50},
{616,13,13,13,41},
{616,26,14,13,33},
{616,40,13,13,56},
{616,53,13,13,61},
{616,66,13,13,46},
{616,79,13,13,44},
{616,118,14,13,47},
{616,132,13,13,39},
{616,184,14,13,36},
{616,198,13,13,50},
{616,211,13,13,47},
{616,250,13,13,40},
{616,263,27,13,36},
{616,290,13,13,39},
{616,303,13,13,43},
{616,0,13,26,36},
{616,92,13,26,42},
{616,145,13,26,36},
{616,224,26,26,42},
{629,13,13,13,38},
{629,26,14,13,36},
{629,53,13,13,60},
{629,66,13,13,52},
{629,79,13,13,47},
{629,105,27,13,50},
{629,132,13,13,33},
{629,184,14,13,33},
{629,198,13,13,49},
{629,263,53,13,36},
{629,40,13,26,63},
{629,211,13,26,53},
{629,250,13,26,43},
{642,26,14,13,57},
{642,53,13,13,55},
{642,66,13,13,50},
{642,92,13,13,44},
{642,105,13,13,49},
{642,132,13,13,40},
{642,145,13,13,37},
{642,184,14,13,39},
{642,198,13,13,43},
{642,224,13,13,47},
{642,263,13,13,40},
{642,276,14,13,39},
{616,158,13,52,39},
{616,171,13,52,40},
{642,0,13,26,41},
{642,13,13,26,33},
{642,79,13,26,40},
{642,118,14,26,54},
{642,237,13,26,42},
{642,290,26,26,36},
{655,26,14,13,63},
{655,40,13,13,61},
{655,53,13,13,51},
{655,92,13,13,42},
{655,105,13,13,46},
{655,132,13,13,44},
{655,145,13,13,40},
{655,184,14,13,44},
{655,198,13,13,42},
{655,211,26,13,52},
{655,250,13,13,46},
{655,276,14,13,40},
{655,66,13,26,54},
{655,263,13,26,45},
{668,0,13,13,36},
{668,13,13,13,41},
{668,40,13,13,59},
{668,92,26,13,39},
{668,118,14,13,52},
{668,132,13,13,48},
{668,145,13,13,44},
{668,158,13,13,42},
{668,171,13,13,39},
{668,184,27,13,42},
{668,211,13,13,48},
{668,224,13,13,54},
{668,237,13,13,44},
{668,276,14,13,43},
{668,290,13,13,34},
{668,303,13,13,36},
{668,26,14,26,64},
{668,53,13,26,48},
{681,13,13,13,54},
{681,40,13,13,51},
{681,66,13,13,46},
{681,118,14,13,50},
{681,132,13,13,52},
{681,145,13,13,40},
{681,158,13,13,43},
{681,171,40,13,42},
{681,211,13,13,46},
{681,224,13,13,55},
{681,237,13,13,49},
{681,263,13,13,48},
{681,276,14,13,46},
{681,290,13,13,40},
{681,303,13,13,34},
{668,79,13,39,44},
{668,250,13,39,43},
{681,0,13,26,33},
{681,92,13,26,39},
{681,105,13,26,33},
{694,13,27,13,62},
{694,40,13,13,48},
{694,53,13,13,51},
{694,66,13,13,35},
{694,118,14,13,46},
{694,145,13,13,42},
{694,158,26,13,40},
{694,184,14,13,44},
{694,198,13,13,45},
{694,211,13,13,42},
{694,224,13,13,54},
{694,237,13,13,56},
{694,263,27,13,48},
{694,290,13,13,44},
{694,303,13,13,39},
{694,132,13,26,54},
{707,0,13,13,41},
{707,26,14,13,55},
{707,40,13,13,51},
{707,66,39,13,39},
{707,105,13,13,36},
{707,145,13,13,47},
{707,171,13,13,40},
{707,198,13,13,47},
{707,211,13,13,44},
{707,250,13,13,47},
{707,263,13,13,46},
{707,276,14,13,48},
{707,290,13,13,45},
{707,13,13,27,63},
{707,158,13,27,39},
{707,184,14,27,42},
{707,224,13,27,50},
{707,237,13,27,60},
{707,303,13,27,42},
{720,0,13,14,58},
{720,26,14,14,46},
{720,92,26,14,41},
{720,132,13,14,51},
{720,145,13,14,53},
{720,171,13,14,44},
{720,198,13,14,44},
{720,211,13,14,54},
{720,250,13,14,54},
{720,276,27,14,48},
{707,53,13,40,48},
{707,118,14,40,33},
{720,79,13,27,36},
{720,263,13,27,40},
{734,0,13,13,63},
{734,13,13,13,60},
{734,26,14,13,38},
{734,92,13,13,41},
{734,132,13,13,41},
{734,145,13,13,57},
{734,158,26,13,44},
{734,184,14,13,45},
{734,198,13,13,40},
{734,211,13,13,49},
{734,224,13,13,58},
{734,250,13,13,59},
{734,276,14,13,48},
{734,105,13,26,43},
{734,237,13,26,61},
{734,290,13,26,51},
{734,303,13,26,43},
{747,0,13,13,62},
{747,79,26,13,36},
{747,118,14,13,40},
{747,145,13,13,54},
{747,158,13,13,50},
{747,171,13,13,44},
{747,184,14,13,47},
{747,198,26,13,42},
{747,224,13,13,52},
{747,250,13,13,62},
{747,263,27,13,46},
{720,40,13,53,55},
{747,13,13,26,51},
{747,53,13,26,46},
{747,132,13,26,33},
{760,0,13,13,59},
{760,79,13,13,36},
{760,92,13,13,34},
{760,105,13,13,40},
{760,145,13,13,47},
{760,171,13,13,42},
{760,198,13,13,42},
{760,211,13,13,44},
{760,224,13,13,46},
{760,237,13,13,56},
{760,250,13,13,63},
{760,263,13,13,52},
{760,290,26,13,48},
{747,26,14,39,46},
{760,118,14,26,45},
{760,158,13,26,53},
{760,184,14,26,49},
{760,276,14,26,46},
{773,0,13,13,55},
{773,13,13,13,41},
{773,53,13,13,43},
{773,79,39,13,36},
{773,132,13,13,43},
{773,145,13,13,39},
{773,171,13,13,45},
{773,198,13,13,45},
{773,211,13,13,42},
{773,224,13,13,43},
{773,250,13,13,62},
{773,263,13,13,60},
{773,290,26,13,51},
{720,66,13,79,39},
{773,40,13,26,52},
{773,237,13,26,51},
{786,13,13,13,43},
{786,26,14,13,44},
{786,53,13,13,42},
{786,79,26,13,36},
{786,105,13,13,34},
{786,118,14,13,41},
{786,132,13,13,46},
{786,145,13,13,35},
{786,158,26,13,50},
{786,184,27,13,47},
{786,211,13,13,38},
{786,224,13,13,41},
{786,250,13,13,61},
{786,263,13,13,62},
{786,276,14,13,48},
{786,290,13,13,51},
}
_G.U5ArtR = {
{0,30,861,1,500},
{1,22,877,1,500},
{2,19,883,1,500},
{3,17,887,1,500},
{4,15,891,1,500},
{5,13,895,1,500},
{6,12,897,1,500},
{7,11,899,1,500},
{8,10,901,1,500},
{9,9,903,1,500},
{10,8,905,1,500},
{11,7,907,1,500},
{12,6,909,1,500},
{13,5,911,2,500},
{15,4,913,1,500},
{16,3,915,3,500},
{19,2,917,2,500},
{21,1,919,4,500},
{25,0,921,749,500},
{774,1,919,4,500},
{778,2,917,2,500},
{780,3,915,3,500},
{783,4,913,1,500},
{784,5,911,2,500},
{786,6,909,1,500},
{787,7,907,1,500},
{788,8,905,1,500},
{789,9,903,1,500},
{790,10,901,1,500},
{791,11,899,1,500},
{792,12,897,1,500},
{793,13,895,1,500},
{794,15,891,1,500},
{795,17,887,1,500},
{796,19,883,1,500},
{797,22,877,1,500},
{798,30,861,1,500},
{0,13,26,13,4},
{0,52,13,13,18},
{0,91,13,13,15},
{0,117,26,13,12},
{0,143,13,13,8},
{0,156,13,13,17},
{0,208,13,13,14},
{0,221,12,13,11},
{0,233,13,13,26},
{0,246,13,13,19},
{0,259,26,13,6},
{0,285,13,13,11},
{0,311,26,13,17},
{0,337,13,13,8},
{0,350,39,13,9},
{0,389,13,13,10},
{0,402,13,13,13},
{0,415,13,13,12},
{0,428,13,13,26},
{0,441,13,13,20},
{0,454,13,13,8},
{0,467,13,13,10},
{0,480,13,13,6},
{0,493,13,13,17},
{0,506,13,13,19},
{0,519,13,13,11},
{0,545,13,13,21},
{0,558,13,13,15},
{0,571,13,13,8},
{0,584,13,13,10},
{0,597,13,13,14},
{0,636,13,13,8},
{0,649,13,13,23},
{0,662,13,13,28},
{0,675,13,13,23},
{0,688,12,13,21},
{0,700,39,13,16},
{0,739,26,13,18},
{0,765,13,13,21},
{0,778,13,13,22},
{0,791,13,13,18},
{0,804,13,13,13},
{0,817,13,13,8},
{0,830,78,13,4},
{0,39,13,26,1},
{0,65,13,26,21},
{0,169,13,26,12},
{0,532,13,26,16},
{0,610,26,26,16},
{13,52,13,13,19},
{13,91,13,13,13},
{13,117,26,13,15},
{13,143,13,13,2},
{13,156,13,13,15},
{13,221,12,13,14},
{13,233,13,13,25},
{13,246,13,13,20},
{13,259,13,13,8},
{13,311,13,13,13},
{13,337,13,13,9},
{13,350,13,13,10},
{13,363,13,13,8},
{13,376,13,13,10},
{13,389,13,13,8},
{13,402,26,13,13},
{13,428,13,13,19},
{13,441,13,13,26},
{13,454,13,13,17},
{13,467,13,13,13},
{13,480,13,13,10},
{13,493,13,13,9},
{13,506,26,13,20},
{13,545,13,13,18},
{13,558,13,13,19},
{13,571,13,13,11},
{13,584,13,13,9},
{13,636,13,13,14},
{13,649,13,13,13},
{13,662,13,13,25},
{13,675,13,13,28},
{13,688,12,13,23},
{13,700,26,13,18},
{13,726,39,13,16},
{13,765,13,13,18},
{13,778,26,13,22},
{13,804,13,13,17},
{13,817,13,13,13},
{13,830,13,13,9},
{13,843,26,13,6},
{0,78,13,39,8},
{0,104,13,39,8},
{0,195,13,39,8},
{0,298,13,39,15},
{13,208,13,26,13},
{13,272,13,26,6},
{13,285,13,26,8},
{13,324,13,26,20},
{13,597,13,26,13},
{13,869,52,26,4},
{26,39,13,13,2},
{26,52,13,13,23},
{26,65,13,13,18},
{26,91,13,13,14},
{26,143,13,13,1},
{26,156,13,13,13},
{26,233,26,13,23},
{26,259,13,13,13},
{26,311,13,13,12},
{26,337,13,13,14},
{26,350,39,13,10},
{26,389,13,13,11},
{26,415,13,13,14},
{26,428,13,13,13},
{26,441,26,13,25},
{26,467,13,13,17},
{26,480,13,13,13},
{26,493,26,13,11},
{26,519,13,13,26},
{26,532,13,13,23},
{26,545,13,13,16},
{26,558,13,13,18},
{26,571,13,13,17},
{26,584,13,13,10},
{26,623,39,13,16},
{26,662,13,13,12},
{26,675,13,13,25},
{26,688,12,13,30},
{26,700,13,13,25},
{26,713,13,13,16},
{26,726,13,13,18},
{26,739,52,13,16},
{26,791,26,13,22},
{26,817,13,13,15},
{26,830,13,13,13},
{26,843,13,13,10},
{0,182,13,52,1},
{13,0,39,39,4},
{26,221,12,26,17},
{26,402,13,26,8},
{26,610,13,26,14},
{26,856,13,26,9},
{39,39,13,13,7},
{39,65,13,13,16},
{39,78,13,13,10},
{39,91,13,13,15},
{39,143,13,13,4},
{39,156,13,13,9},
{39,208,13,13,10},
{39,233,13,13,20},
{39,246,13,13,23},
{39,259,13,13,17},
{39,272,13,13,8},
{39,285,13,13,9},
{39,298,13,13,13},
{39,311,13,13,11},
{39,324,26,13,19},
{39,350,26,13,13},
{39,376,13,13,8},
{39,415,13,13,13},
{39,428,13,13,14},
{39,441,13,13,23},
{39,454,13,13,26},
{39,467,13,13,23},
{39,480,13,13,15},
{39,493,13,13,12},
{39,506,13,13,6},
{39,519,13,13,15},
{39,532,13,13,25},
{39,545,39,13,21},
{39,584,13,13,16},
{39,597,13,13,8},
{39,623,13,13,17},
{39,636,26,13,18},
{39,662,13,13,15},
{39,675,13,13,12},
{39,688,12,13,28},
{39,700,13,13,30},
{39,713,13,13,22},
{39,726,13,13,16},
{39,739,26,13,18},
{39,765,13,13,21},
{39,778,26,13,16},
{39,804,13,13,22},
{39,817,13,13,18},
{39,830,13,13,8},
{39,843,13,13,11},
{39,869,13,13,1},
{39,882,39,13,4},
{26,130,13,39,19},
{26,169,13,39,15},
{39,389,13,26,13},
{52,39,13,13,12},
{52,78,13,13,11},
{52,91,13,13,17},
{52,143,13,13,11},
{52,182,13,13,11},
{52,221,12,13,14},
{52,272,13,13,10},
{52,298,26,13,10},
{52,324,13,13,13},
{52,337,13,13,20},
{52,350,13,13,15},
{52,376,13,13,10},
{52,402,13,13,12},
{52,441,13,13,15},
{52,454,13,13,30},
{52,467,13,13,25},
{52,480,13,13,23},
{52,493,13,13,15},
{52,506,13,13,12},
{52,519,13,13,6},
{52,532,13,13,20},
{52,558,13,13,23},
{52,571,13,13,25},
{52,584,13,13,21},
{52,597,13,13,17},
{52,610,13,13,12},
{52,623,13,13,19},
{52,636,13,13,16},
{52,649,26,13,18},
{52,675,13,13,15},
{52,688,12,13,17},
{52,700,26,13,30},
{52,726,13,13,21},
{52,778,13,13,23},
{52,791,13,13,21},
{52,804,13,13,16},
{52,817,13,13,21},
{52,830,13,13,12},
{52,843,13,13,9},
{52,856,13,13,10},
{52,869,13,13,12},
{52,882,13,13,7},
{52,895,26,13,4},
{26,117,13,53,17},
{39,104,13,40,6},
{39,195,13,40,9},
{52,0,26,27,4},
{52,156,13,27,6},
{52,208,13,27,8},
{52,233,26,27,20},
{52,285,13,27,8},
{52,363,13,27,13},
{52,415,13,27,8},
{52,428,13,27,13},
{52,545,13,27,28},
{52,739,39,27,18},
{65,39,13,14,15},
{65,78,13,14,13},
{65,130,13,14,21},
{65,143,13,14,15},
{65,169,13,14,12},
{65,221,12,14,13},
{65,272,13,14,17},
{65,298,13,14,10},
{65,311,13,14,9},
{65,324,13,14,11},
{65,337,26,14,19},
{65,376,13,14,14},
{65,389,13,14,11},
{65,441,13,14,11},
{65,454,13,14,25},
{65,467,13,14,29},
{65,480,26,14,23},
{65,506,13,14,15},
{65,519,13,14,10},
{65,532,13,14,1},
{65,558,13,14,29},
{65,571,26,14,28},
{65,597,13,14,23},
{65,610,13,14,15},
{65,623,13,14,17},
{65,636,13,14,19},
{65,649,13,14,17},
{65,662,13,14,19},
{65,675,13,14,18},
{65,688,12,14,14},
{65,700,13,14,22},
{65,713,13,14,31},
{65,726,13,14,29},
{65,778,13,14,22},
{65,791,13,14,28},
{65,804,13,14,23},
{65,817,13,14,16},
{65,830,13,14,18},
{65,843,13,14,11},
{65,856,13,14,9},
{65,869,26,14,13},
{65,895,13,14,9},
{65,908,13,14,4},
{52,65,13,40,17},
{52,259,13,40,19},
{65,182,13,27,13},
{65,402,13,27,15},
{79,39,13,13,18},
{79,78,13,13,14},
{79,104,13,13,8},
{79,130,13,13,18},
{79,143,13,13,17},
{79,156,13,13,1},
{79,169,13,13,7},
{79,195,13,13,8},
{79,233,13,13,19},
{79,285,13,13,11},
{79,298,26,13,9},
{79,324,13,13,10},
{79,337,13,13,17},
{79,350,13,13,23},
{79,363,13,13,17},
{79,376,26,13,12},
{79,415,13,13,13},
{79,428,13,13,10},
{79,454,13,13,14},
{79,467,13,13,28},
{79,480,13,13,26},
{79,493,13,13,25},
{79,506,13,13,20},
{79,519,13,13,17},
{79,532,13,13,14},
{79,545,13,13,17},
{79,558,13,13,30},
{79,571,13,13,31},
{79,584,13,13,30},
{79,597,13,13,28},
{79,610,13,13,23},
{79,623,13,13,15},
{79,636,13,13,20},
{79,649,13,13,19},
{79,675,25,13,21},
{79,700,13,13,12},
{79,713,13,13,28},
{79,726,13,13,31},
{79,739,13,13,28},
{79,752,26,13,21},
{79,778,13,13,18},
{79,791,13,13,25},
{79,804,13,13,28},
{79,817,13,13,23},
{79,830,26,13,18},
{79,856,13,13,11},
{79,869,13,13,8},
{79,882,13,13,9},
{79,895,13,13,10},
{79,908,13,13,11},
{65,91,13,40,19},
{79,117,13,26,15},
{79,221,12,26,14},
{79,272,13,26,21},
{79,441,13,26,17},
{79,662,13,26,18},
{92,39,13,13,19},
{92,65,13,13,18},
{92,78,13,13,12},
{92,104,13,13,9},
{92,156,13,13,7},
{92,182,26,13,11},
{92,233,13,13,17},
{92,259,13,13,18},
{92,285,13,13,15},
{92,298,26,13,8},
{92,324,26,13,10},
{92,350,13,13,19},
{92,376,13,13,13},
{92,389,13,13,15},
{92,402,13,13,16},
{92,428,13,13,8},
{92,454,13,13,15},
{92,467,39,13,23},
{92,506,39,13,26},
{92,545,13,13,23},
{92,571,13,13,28},
{92,584,26,13,30},
{92,610,13,13,25},
{92,623,13,13,21},
{92,636,13,13,18},
{92,649,13,13,23},
{92,700,13,13,21},
{92,713,13,13,16},
{92,726,13,13,30},
{92,739,13,13,31},
{92,752,13,13,28},
{92,765,26,13,21},
{92,791,13,13,22},
{92,804,26,13,23},
{92,830,13,13,25},
{92,856,13,13,21},
{92,869,13,13,13},
{92,882,13,13,8},
{92,895,13,13,9},
{92,908,13,13,8},
{79,0,13,39,4},
{79,13,13,39,7},
{79,208,13,39,10},
{79,246,13,39,23},
{92,169,13,26,1},
{92,363,13,26,20},
{92,415,13,26,15},
{92,558,13,26,19},
{92,675,13,26,21},
{92,688,12,26,18},
{92,843,13,26,22},
{105,65,13,13,21},
{105,78,13,13,15},
{105,91,13,13,18},
{105,104,13,13,13},
{105,117,13,13,12},
{105,156,13,13,12},
{105,182,13,13,12},
{105,195,13,13,13},
{105,221,12,13,17},
{105,233,13,13,14},
{105,259,13,13,21},
{105,298,13,13,12},
{105,311,13,13,10},
{105,324,13,13,13},
{105,337,13,13,10},
{105,350,13,13,15},
{105,376,13,13,17},
{105,389,26,13,16},
{105,428,13,13,11},
{105,441,13,13,8},
{105,454,13,13,18},
{105,467,13,13,15},
{105,480,13,13,19},
{105,493,13,13,23},
{105,506,52,13,26},
{105,571,13,13,17},
{105,584,13,13,20},
{105,597,26,13,29},
{105,623,26,13,18},
{105,649,13,13,21},
{105,662,13,13,23},
{105,700,13,13,19},
{105,713,13,13,22},
{105,726,13,13,16},
{105,739,26,13,31},
{105,765,13,13,27},
{105,778,39,13,22},
{105,817,13,13,16},
{105,830,13,13,17},
{105,856,26,13,23},
{105,882,13,13,17},
{105,895,13,13,8},
{105,908,13,13,2},
{39,52,13,92,25},
{52,26,13,79,1},
{92,130,13,39,16},
{105,39,13,26,23},
{105,272,26,26,18},
{118,0,26,13,4},
{118,78,13,13,16},
{118,91,13,13,19},
{118,117,13,13,11},
{118,156,13,13,16},
{118,182,13,13,11},
{118,195,13,13,10},
{118,208,13,13,8},
{118,221,12,13,14},
{118,233,13,13,17},
{118,246,13,13,18},
{118,259,13,13,23},
{118,298,13,13,16},
{118,311,13,13,11},
{118,324,13,13,14},
{118,337,13,13,13},
{118,350,13,13,10},
{118,363,26,13,19},
{118,389,39,13,16},
{118,428,13,13,14},
{118,441,13,13,10},
{118,454,13,13,13},
{118,467,13,13,20},
{118,480,13,13,23},
{118,493,13,13,19},
{118,519,13,13,20},
{118,532,13,13,26},
{118,545,13,13,28},
{118,558,13,13,29},
{118,571,13,13,23},
{118,584,13,13,28},
{118,597,26,13,32},
{118,623,13,13,31},
{118,636,39,13,25},
{118,675,13,13,22},
{118,688,25,13,21},
{118,713,26,13,22},
{118,739,13,13,18},
{118,752,26,13,31},
{118,778,13,13,27},
{118,791,13,13,22},
{118,804,13,13,23},
{118,817,13,13,15},
{118,830,26,13,8},
{118,856,13,13,15},
{118,869,13,13,19},
{118,882,13,13,20},
{118,895,13,13,17},
{92,143,13,52,18},
{118,65,13,26,22},
{118,104,13,26,17},
{118,169,13,26,2},
{118,506,13,26,17},
{118,908,13,26,15},
{131,0,39,13,4},
{131,39,13,13,22},
{131,52,13,13,24},
{131,117,13,13,10},
{131,130,13,13,12},
{131,156,13,13,19},
{131,182,39,13,8},
{131,259,26,13,25},
{131,285,13,13,21},
{131,311,13,13,12},
{131,324,13,13,13},
{131,337,13,13,15},
{131,350,13,13,17},
{131,363,13,13,14},
{131,376,13,13,21},
{131,389,13,13,16},
{131,402,13,13,18},
{131,415,13,13,15},
{131,428,26,13,16},
{131,454,13,13,8},
{131,467,13,13,19},
{131,480,13,13,29},
{131,493,13,13,20},
{131,519,26,13,20},
{131,545,13,13,31},
{131,558,26,13,32},
{131,584,13,13,29},
{131,597,39,13,32},
{131,636,13,13,31},
{131,649,13,13,30},
{131,662,13,13,28},
{131,675,13,13,27},
{131,688,38,13,21},
{131,726,13,13,25},
{131,739,13,13,21},
{131,752,13,13,22},
{131,765,26,13,31},
{131,791,26,13,25},
{131,817,13,13,18},
{131,830,13,13,13},
{131,856,13,13,6},
{131,869,13,13,2},
{131,882,13,13,7},
{131,895,13,13,12},
{131,78,26,26,18},
{131,221,12,26,13},
{131,233,26,26,18},
{131,298,13,26,18},
{144,0,26,13,4},
{144,39,13,13,23},
{144,52,26,13,24},
{144,104,13,13,19},
{144,117,13,13,14},
{144,130,13,13,11},
{144,143,13,13,16},
{144,156,13,13,22},
{144,169,13,13,12},
{144,195,26,13,8},
{144,259,13,13,21},
{144,272,13,13,28},
{144,285,13,13,23},
{144,311,13,13,16},
{144,324,13,13,11},
{144,337,13,13,14},
{144,363,13,13,15},
{144,376,26,13,18},
{144,402,52,13,16},
{144,454,13,13,13},
{144,467,13,13,6},
{144,480,13,13,28},
{144,506,13,13,23},
{144,519,13,13,25},
{144,532,13,13,31},
{144,545,52,13,32},
{144,597,13,13,31},
{144,610,39,13,32},
{144,649,13,13,31},
{144,662,13,13,26},
{144,675,13,13,25},
{144,688,12,13,23},
{144,726,13,13,21},
{144,739,13,13,28},
{144,752,13,13,21},
{144,765,13,13,27},
{144,778,13,13,31},
{144,791,13,13,28},
{144,804,26,13,22},
{144,830,13,13,14},
{144,856,13,13,8},
{144,869,26,13,4},
{144,895,26,13,1},
{131,843,13,39,10},
{144,182,13,26,6},
{144,350,13,26,19},
{144,493,13,26,29},
{144,700,13,26,21},
{144,713,13,26,16},
{157,13,13,13,3},
{157,52,26,13,27},
{157,78,13,13,22},
{157,91,13,13,21},
{157,117,13,13,20},
{157,130,13,13,6},
{157,143,13,13,13},
{157,156,13,13,21},
{157,169,13,13,19},
{157,195,13,13,8},
{157,208,13,13,11},
{157,221,12,13,10},
{157,233,13,13,16},
{157,246,26,13,18},
{157,272,13,13,27},
{157,285,13,13,29},
{157,298,26,13,18},
{157,324,13,13,15},
{157,337,13,13,17},
{157,376,13,13,12},
{157,389,13,13,21},
{157,402,26,13,18},
{157,428,13,13,16},
{157,441,13,13,12},
{157,454,13,13,15},
{157,467,13,13,11},
{157,480,13,13,17},
{157,506,13,13,26},
{157,519,13,13,29},
{157,623,13,13,10},
{157,636,13,13,29},
{157,662,13,13,25},
{157,675,13,13,18},
{157,739,13,13,23},
{157,752,13,13,30},
{157,765,13,13,21},
{157,778,13,13,28},
{157,791,13,13,30},
{157,804,13,13,22},
{157,817,13,13,24},
{157,830,13,13,18},
{157,856,13,13,11},
{157,869,52,13,4},
{144,26,13,39,7},
{157,363,13,26,23},
{157,532,91,26,32},
{157,649,13,26,32},
{157,688,12,26,17},
{157,726,13,26,12},
{170,52,13,13,28},
{170,65,13,13,27},
{170,78,26,13,23},
{170,117,13,13,28},
{170,130,13,13,15},
{170,143,13,13,10},
{170,156,13,13,16},
{170,169,13,13,20},
{170,182,39,13,8},
{170,233,13,13,12},
{170,259,26,13,21},
{170,285,13,13,31},
{170,298,13,13,28},
{170,311,13,13,21},
{170,324,13,13,19},
{170,337,13,13,14},
{170,350,13,13,13},
{170,376,13,13,20},
{170,389,13,13,16},
{170,402,26,13,21},
{170,428,13,13,18},
{170,441,13,13,16},
{170,454,13,13,12},
{170,467,13,13,13},
{170,493,26,13,26},
{170,519,13,13,31},
{170,623,26,13,26},
{170,662,13,13,30},
{170,675,13,13,25},
{170,700,13,13,16},
{170,713,13,13,18},
{170,739,13,13,15},
{170,752,13,13,29},
{170,765,13,13,31},
{170,778,13,13,21},
{170,791,13,13,28},
{170,804,13,13,27},
{170,817,26,13,21},
{170,843,13,13,13},
{170,856,13,13,10},
{170,869,13,13,6},
{170,882,39,13,4},
{157,39,13,39,25},
{157,104,13,39,22},
{170,221,12,26,13},
{170,246,13,26,18},
{170,480,13,26,8},
{183,26,13,13,12},
{183,52,26,13,28},
{183,78,13,13,25},
{183,91,13,13,27},
{183,117,26,13,28},
{183,143,13,13,8},
{183,156,13,13,12},
{183,169,13,13,23},
{183,182,13,13,15},
{183,195,13,13,8},
{183,208,13,13,10},
{183,233,13,13,15},
{183,259,13,13,19},
{183,272,13,13,17},
{183,285,26,13,30},
{183,311,13,13,18},
{183,324,13,13,17},
{183,337,26,13,14},
{183,363,13,13,17},
{183,376,13,13,28},
{183,389,13,13,19},
{183,402,13,13,18},
{183,415,26,13,23},
{183,441,13,13,18},
{183,454,13,13,16},
{183,467,13,13,15},
{183,493,13,13,19},
{183,506,13,13,26},
{183,519,13,13,29},
{183,532,13,13,31},
{183,545,78,13,32},
{183,623,13,13,20},
{183,636,13,13,29},
{183,649,39,13,26},
{183,688,12,13,28},
{183,700,13,13,19},
{183,713,13,13,16},
{183,726,26,13,12},
{183,752,13,13,21},
{183,765,26,13,31},
{183,791,13,13,22},
{183,804,26,13,21},
{183,830,13,13,22},
{183,843,13,13,14},
{183,856,13,13,13},
{183,869,13,13,11},
{183,882,13,13,2},
{183,895,26,13,4},
{196,26,13,14,15},
{196,39,13,14,22},
{196,52,13,14,30},
{196,65,13,14,28},
{196,78,39,14,27},
{196,117,13,14,23},
{196,130,13,14,31},
{196,143,13,14,23},
{196,156,13,14,6},
{196,169,13,14,16},
{196,182,13,14,21},
{196,195,13,14,11},
{196,208,13,14,9},
{196,221,12,14,12},
{196,233,13,14,18},
{196,246,13,14,16},
{196,259,13,14,21},
{196,272,13,14,23},
{196,285,13,14,26},
{196,298,13,14,29},
{196,311,13,14,26},
{196,324,26,14,20},
{196,350,13,14,17},
{196,363,13,14,10},
{196,376,13,14,25},
{196,389,13,14,29},
{196,402,13,14,21},
{196,415,13,14,17},
{196,441,13,14,21},
{196,454,26,14,16},
{196,493,13,14,10},
{196,506,13,14,23},
{196,532,13,14,13},
{196,545,39,14,32},
{196,597,26,14,32},
{196,623,13,14,17},
{196,636,13,14,20},
{196,649,13,14,17},
{196,662,13,14,26},
{196,675,13,14,29},
{196,688,12,14,20},
{196,700,13,14,31},
{196,713,13,14,18},
{196,726,13,14,12},
{196,739,13,14,15},
{196,765,13,14,23},
{196,778,13,14,31},
{196,804,13,14,16},
{196,830,26,14,19},
{196,856,26,14,10},
{196,882,39,14,4},
{196,428,13,27,23},
{196,480,13,27,15},
{196,584,13,27,29},
{196,791,13,27,30},
{196,817,13,27,15},
{210,39,13,13,19},
{210,52,13,13,29},
{210,65,13,13,30},
{210,78,39,13,28},
{210,117,13,13,16},
{210,130,13,13,30},
{210,156,13,13,16},
{210,169,13,13,12},
{210,182,13,13,23},
{210,195,13,13,16},
{210,208,13,13,8},
{210,221,12,13,11},
{210,233,13,13,17},
{210,246,26,13,18},
{210,272,13,13,25},
{210,285,13,13,23},
{210,298,26,13,28},
{210,324,13,13,23},
{210,337,26,13,17},
{210,363,26,13,13},
{210,389,13,13,30},
{210,402,13,13,29},
{210,415,13,13,21},
{210,454,13,13,21},
{210,467,13,13,16},
{210,493,13,13,13},
{210,506,13,13,17},
{210,532,13,13,2},
{210,545,13,13,23},
{210,558,13,13,32},
{210,571,13,13,31},
{210,597,13,13,32},
{210,610,13,13,31},
{210,623,13,13,20},
{210,636,13,13,17},
{210,649,13,13,14},
{210,688,12,13,19},
{210,700,13,13,29},
{210,726,13,13,16},
{210,739,13,13,12},
{210,765,13,13,18},
{210,778,13,13,27},
{210,804,13,13,28},
{210,830,13,13,14},
{210,843,13,13,19},
{210,856,13,13,13},
{210,882,13,13,6},
{196,519,13,40,20},
{210,26,13,26,17},
{210,143,13,26,31},
{210,441,13,26,25},
{210,662,13,26,29},
{210,675,13,26,32},
{223,39,13,13,14},
{223,52,13,13,26},
{223,78,13,13,28},
{223,91,26,13,30},
{223,117,13,13,22},
{223,130,13,13,18},
{223,156,13,13,28},
{223,169,13,13,11},
{223,182,13,13,17},
{223,195,13,13,21},
{223,208,13,13,11},
{223,233,13,13,18},
{223,259,13,13,16},
{223,272,13,13,23},
{223,285,13,13,25},
{223,298,13,13,29},
{223,311,26,13,32},
{223,337,13,13,29},
{223,350,13,13,26},
{223,363,13,13,19},
{223,376,13,13,10},
{223,389,13,13,19},
{223,402,13,13,31},
{223,415,13,13,26},
{223,428,13,13,19},
{223,454,13,13,28},
{223,467,13,13,23},
{223,480,13,13,16},
{223,493,13,13,10},
{223,506,13,13,8},
{223,532,13,13,17},
{223,545,13,13,1},
{223,558,13,13,15},
{223,571,26,13,26},
{223,597,13,13,20},
{223,610,13,13,17},
{223,623,26,13,14},
{223,649,13,13,13},
{223,688,12,13,26},
{223,700,13,13,25},
{223,726,13,13,29},
{223,739,13,13,15},
{223,778,26,13,25},
{223,804,26,13,28},
{223,830,13,13,19},
{223,843,26,13,17},
{223,882,13,13,8},
{196,752,13,53,16},
{210,713,13,39,31},
{210,869,13,39,10},
{210,895,26,39,4},
{223,65,13,26,31},
{223,221,12,26,13},
{236,26,13,13,18},
{236,39,13,13,15},
{236,52,13,13,20},
{236,78,26,13,30},
{236,117,13,13,28},
{236,130,13,13,16},
{236,143,13,13,22},
{236,156,13,13,30},
{236,169,13,13,25},
{236,182,13,13,11},
{236,195,13,13,20},
{236,208,13,13,19},
{236,233,13,13,15},
{236,259,26,13,25},
{236,285,13,13,30},
{236,298,13,13,31},
{236,363,13,13,29},
{236,376,13,13,17},
{236,389,13,13,10},
{236,402,13,13,26},
{236,415,13,13,29},
{236,428,13,13,26},
{236,441,13,13,19},
{236,454,13,13,25},
{236,467,13,13,31},
{236,480,13,13,29},
{236,493,13,13,19},
{236,506,13,13,13},
{236,519,13,13,10},
{236,532,13,13,26},
{236,545,13,13,15},
{236,558,13,13,6},
{236,571,13,13,2},
{236,584,13,13,6},
{236,597,13,13,10},
{236,610,26,13,13},
{236,636,13,13,14},
{236,649,13,13,6},
{236,662,13,13,32},
{236,675,13,13,31},
{236,688,12,13,29},
{236,700,13,13,26},
{236,726,13,13,28},
{236,739,13,13,25},
{236,791,13,13,28},
{236,804,13,13,21},
{236,817,13,13,25},
{236,830,13,13,23},
{236,843,13,13,19},
{236,856,13,13,17},
{236,882,13,13,6},
{223,246,13,39,21},
{223,765,13,39,21},
{236,104,13,26,31},
{236,311,39,26,32},
{236,350,13,26,31},
{236,778,13,26,22},
{249,26,13,13,17},
{249,39,26,13,14},
{249,65,39,13,30},
{249,117,13,13,30},
{249,130,13,13,22},
{249,156,13,13,23},
{249,169,13,13,29},
{249,182,13,13,23},
{249,195,13,13,17},
{249,208,13,13,23},
{249,221,12,13,17},
{249,233,13,13,16},
{249,285,26,13,30},
{249,363,13,13,30},
{249,376,13,13,25},
{249,389,13,13,14},
{249,402,13,13,17},
{249,415,13,13,20},
{249,428,13,13,25},
{249,441,13,13,26},
{249,454,13,13,19},
{249,467,13,13,23},
{249,480,26,13,29},
{249,506,13,13,26},
{249,519,13,13,17},
{249,532,13,13,19},
{249,545,13,13,25},
{249,558,13,13,15},
{249,584,78,13,13},
{249,662,13,13,31},
{249,675,13,13,26},
{249,688,12,13,31},
{249,700,13,13,28},
{249,713,13,13,32},
{249,726,13,13,29},
{249,739,13,13,28},
{249,752,13,13,22},
{249,817,13,13,18},
{249,843,13,13,13},
{249,856,13,13,19},
{249,869,13,13,14},
{249,882,13,13,8},
{249,895,13,13,1},
{249,908,13,13,4},
{249,259,13,26,30},
{249,272,13,26,31},
{249,571,13,26,9},
{249,804,13,26,28},
{249,830,13,26,19},
{262,26,13,13,15},
{262,39,26,13,13},
{262,65,13,13,26},
{262,91,13,13,30},
{262,104,26,13,31},
{262,130,13,13,28},
{262,156,13,13,25},
{262,169,13,13,22},
{262,182,13,13,25},
{262,195,13,13,18},
{262,208,25,13,23},
{262,233,13,13,18},
{262,246,13,13,23},
{262,285,13,13,28},
{262,298,13,13,26},
{262,311,13,13,29},
{262,324,39,13,32},
{262,363,26,13,29},
{262,389,13,13,19},
{262,402,13,13,14},
{262,415,13,13,25},
{262,428,13,13,14},
{262,441,13,13,19},
{262,454,13,13,23},
{262,467,13,13,20},
{262,480,13,13,19},
{262,493,13,13,20},
{262,506,26,13,26},
{262,532,26,13,20},
{262,558,13,13,19},
{262,584,13,13,5},
{262,597,13,13,9},
{262,610,39,13,13},
{262,649,13,13,14},
{262,675,13,13,20},
{262,688,12,13,32},
{262,700,13,13,30},
{262,713,26,13,31},
{262,739,26,13,28},
{262,765,13,13,22},
{262,817,13,13,25},
{262,843,26,13,14},
{262,869,13,13,19},
{262,882,13,13,14},
{262,895,13,13,12},
{262,908,13,13,7},
{249,143,13,39,21},
{262,78,13,26,31},
{262,662,13,26,29},
{262,778,13,26,23},
{275,26,26,13,11},
{275,65,13,13,23},
{275,91,26,13,30},
{275,117,13,13,31},
{275,130,13,13,30},
{275,156,13,13,27},
{275,169,13,13,23},
{275,182,26,13,22},
{275,208,13,13,16},
{275,221,12,13,25},
{275,246,13,13,30},
{275,259,13,13,26},
{275,272,13,13,28},
{275,285,13,13,29},
{275,298,13,13,23},
{275,311,13,13,25},
{275,324,13,13,31},
{275,337,13,13,32},
{275,350,26,13,31},
{275,376,26,13,29},
{275,402,26,13,17},
{275,428,13,13,23},
{275,441,13,13,14},
{275,454,39,13,17},
{275,506,13,13,17},
{275,519,26,13,14},
{275,545,13,13,17},
{275,558,13,13,14},
{275,571,13,13,1},
{275,584,65,13,5},
{275,649,13,13,20},
{275,675,64,13,31},
{275,739,13,13,30},
{275,765,13,13,25},
{275,804,13,13,25},
{275,817,26,13,23},
{275,843,13,13,17},
{275,856,13,13,11},
{275,869,13,13,13},
{275,882,26,13,14},
{275,908,13,13,13},
{249,791,13,52,27},
{275,52,13,26,12},
{275,233,13,26,28},
{275,493,13,26,14},
{275,752,13,26,29},
{288,65,13,13,19},
{288,78,26,13,31},
{288,117,26,13,31},
{288,143,13,13,27},
{288,156,13,13,21},
{288,169,13,13,28},
{288,182,26,13,23},
{288,208,13,13,22},
{288,221,12,13,18},
{288,246,13,13,31},
{288,259,13,13,29},
{288,272,13,13,19},
{288,285,13,13,26},
{288,298,13,13,28},
{288,311,13,13,20},
{288,324,13,13,26},
{288,337,26,13,31},
{288,363,13,13,29},
{288,376,26,13,20},
{288,402,13,13,25},
{288,415,13,13,19},
{288,428,13,13,25},
{288,441,13,13,17},
{288,454,13,13,10},
{288,467,13,13,14},
{288,480,13,13,17},
{288,506,26,13,10},
{288,532,13,13,8},
{288,545,13,13,6},
{288,558,13,13,2},
{288,571,13,13,4},
{288,584,26,13,5},
{288,610,13,13,9},
{288,623,13,13,10},
{288,649,13,13,25},
{288,675,77,13,31},
{288,765,26,13,25},
{288,804,13,13,28},
{288,817,13,13,15},
{288,830,13,13,25},
{288,843,13,13,19},
{288,856,13,13,12},
{288,869,13,13,2},
{288,882,13,13,14},
{288,908,13,13,2},
{288,104,13,26,28},
{288,662,13,26,32},
{301,52,13,13,8},
{301,78,13,13,29},
{301,91,13,13,32},
{301,117,13,13,30},
{301,130,13,13,31},
{301,143,13,13,30},
{301,156,13,13,18},
{301,169,13,13,24},
{301,195,13,13,21},
{301,208,13,13,23},
{301,221,25,13,25},
{301,246,26,13,28},
{301,272,13,13,23},
{301,285,13,13,17},
{301,298,13,13,29},
{301,311,13,13,26},
{301,324,13,13,17},
{301,337,13,13,29},
{301,350,13,13,31},
{301,363,13,13,20},
{301,376,13,13,13},
{301,389,13,13,14},
{301,402,26,13,19},
{301,428,26,13,20},
{301,454,13,13,13},
{301,467,13,13,10},
{301,480,13,13,14},
{301,493,13,13,13},
{301,519,13,13,6},
{301,532,13,13,4},
{301,545,26,13,5},
{301,571,39,13,4},
{301,610,13,13,8},
{301,623,13,13,11},
{301,649,13,13,29},
{301,675,25,13,30},
{301,700,26,13,31},
{301,726,13,13,19},
{301,739,13,13,29},
{301,752,13,13,30},
{301,765,13,13,28},
{301,778,13,13,25},
{301,817,13,13,20},
{301,830,13,13,15},
{301,843,13,13,23},
{301,856,13,13,15},
{301,869,13,13,1},
{301,882,13,13,11},
{301,908,13,13,4},
{288,26,13,39,12},
{288,39,13,39,11},
{288,895,13,39,13},
{301,65,13,26,20},
{301,182,13,26,27},
{301,506,13,26,8},
{301,791,13,26,28},
{314,52,13,13,6},
{314,91,13,13,31},
{314,104,13,13,30},
{314,130,13,13,30},
{314,143,13,13,31},
{314,156,13,13,27},
{314,169,13,13,18},
{314,195,13,13,22},
{314,208,25,13,21},
{314,233,13,13,28},
{314,246,13,13,29},
{314,259,13,13,26},
{314,272,13,13,25},
{314,285,13,13,19},
{314,298,13,13,17},
{314,311,13,13,28},
{314,324,13,13,26},
{314,337,26,13,20},
{314,363,26,13,17},
{314,389,13,13,10},
{314,402,13,13,14},
{314,415,13,13,17},
{314,428,13,13,10},
{314,441,13,13,17},
{314,454,13,13,14},
{314,467,13,13,8},
{314,480,13,13,13},
{314,493,13,13,10},
{314,519,104,13,4},
{314,649,77,13,31},
{314,726,13,13,25},
{314,752,13,13,28},
{314,765,13,13,29},
{314,778,13,13,27},
{314,843,13,13,25},
{314,856,13,13,19},
{314,869,13,13,5},
{314,908,13,13,7},
{288,636,13,53,1},
{301,804,13,40,30},
{314,117,13,27,28},
{314,623,13,27,7},
{314,739,13,27,17},
{314,817,13,27,25},
{314,830,13,27,8},
{314,882,13,27,6},
{327,26,26,14,13},
{327,65,13,14,14},
{327,91,13,14,23},
{327,104,13,14,25},
{327,130,13,14,27},
{327,143,26,14,31},
{327,169,13,14,21},
{327,182,26,14,22},
{327,221,25,14,21},
{327,246,13,14,25},
{327,259,13,14,30},
{327,272,13,14,29},
{327,285,13,14,28},
{327,298,13,14,19},
{327,311,13,14,14},
{327,324,13,14,28},
{327,337,13,14,26},
{327,350,26,14,17},
{327,376,13,14,14},
{327,389,13,14,11},
{327,402,13,14,4},
{327,415,26,14,11},
{327,441,26,14,2},
{327,467,13,14,6},
{327,480,13,14,2},
{327,493,26,14,6},
{327,519,39,14,4},
{327,558,13,14,3},
{327,571,52,14,4},
{327,649,26,14,31},
{327,675,25,14,30},
{327,700,13,14,31},
{327,713,13,14,30},
{327,752,13,14,19},
{327,765,39,14,28},
{327,843,26,14,20},
{327,869,13,14,2},
{327,895,13,14,9},
{327,908,13,14,4},
{314,78,13,40,26},
{327,52,13,27,8},
{327,208,13,27,18},
{341,26,13,13,13},
{341,39,13,13,14},
{341,91,13,13,20},
{341,104,13,13,14},
{341,117,13,13,27},
{341,143,13,13,27},
{341,156,13,13,31},
{341,169,13,13,28},
{341,182,13,13,22},
{341,195,13,13,24},
{341,221,12,13,16},
{341,233,26,13,22},
{341,259,13,13,23},
{341,272,26,13,28},
{341,298,13,13,25},
{341,311,13,13,17},
{341,324,13,13,14},
{341,337,26,13,26},
{341,363,13,13,17},
{341,376,13,13,13},
{341,389,13,13,2},
{341,402,13,13,5},
{341,519,26,13,7},
{341,597,13,13,4},
{341,623,13,13,4},
{341,636,13,13,18},
{341,662,26,13,30},
{341,688,12,13,21},
{341,700,13,13,30},
{341,713,13,13,31},
{341,739,13,13,19},
{341,752,13,13,17},
{341,765,13,13,19},
{341,778,13,13,30},
{341,791,13,13,28},
{341,830,26,13,12},
{341,856,13,13,23},
{341,869,13,13,11},
{341,882,13,13,5},
{157,0,13,210,4},
{170,13,13,197,1},
{327,726,13,40,28},
{341,130,13,26,22},
{341,415,104,26,4},
{341,610,13,26,7},
{341,649,13,26,31},
{341,817,13,26,23},
{354,26,13,13,11},
{354,52,13,13,9},
{354,78,13,13,23},
{354,91,13,13,26},
{354,104,13,13,10},
{354,117,13,13,19},
{354,143,13,13,18},
{354,156,39,13,30},
{354,195,26,13,27},
{354,221,12,13,21},
{354,233,13,13,16},
{354,246,13,13,21},
{354,259,26,13,23},
{354,285,13,13,28},
{354,298,13,13,30},
{354,311,13,13,27},
{354,324,13,13,19},
{354,337,13,13,14},
{354,350,13,13,26},
{354,363,13,13,28},
{354,376,13,13,20},
{354,402,13,13,9},
{354,519,26,13,1},
{354,597,13,13,3},
{354,623,13,13,1},
{354,675,13,13,28},
{354,688,12,13,27},
{354,713,13,13,30},
{354,739,13,13,20},
{354,752,13,13,15},
{354,765,13,13,6},
{354,778,13,13,29},
{354,830,13,13,11},
{354,843,13,13,8},
{354,856,13,13,19},
{354,869,13,13,12},
{341,65,13,39,10},
{341,545,52,39,5},
{341,804,13,39,31},
{354,39,13,26,13},
{354,389,13,26,17},
{354,636,13,26,29},
{354,662,13,26,29},
{354,700,13,26,15},
{354,791,13,26,30},
{354,882,13,26,1},
{367,0,26,13,4},
{367,26,13,13,7},
{367,52,13,13,8},
{367,78,13,13,17},
{367,91,13,13,28},
{367,104,13,13,14},
{367,117,13,13,10},
{367,130,26,13,19},
{367,156,13,13,24},
{367,169,39,13,30},
{367,208,13,13,27},
{367,221,12,13,29},
{367,233,13,13,23},
{367,246,26,13,16},
{367,272,26,13,22},
{367,298,13,13,27},
{367,311,13,13,29},
{367,324,13,13,26},
{367,337,13,13,23},
{367,350,13,13,19},
{367,363,13,13,23},
{367,376,13,13,26},
{367,402,13,13,6},
{367,415,13,13,1},
{367,428,65,13,4},
{367,493,13,13,1},
{367,506,13,13,7},
{367,519,26,13,20},
{367,597,13,13,7},
{367,610,13,13,1},
{367,623,13,13,23},
{367,649,13,13,12},
{367,675,25,13,28},
{367,713,13,13,23},
{367,726,13,13,29},
{367,739,13,13,17},
{367,752,13,13,11},
{367,778,13,13,25},
{367,843,13,13,12},
{367,856,26,13,15},
{367,817,13,26,25},
{380,0,39,13,4},
{380,52,13,13,9},
{380,65,26,13,11},
{380,91,13,13,26},
{380,104,13,13,25},
{380,117,13,13,8},
{380,130,13,13,13},
{380,143,13,13,25},
{380,156,13,13,22},
{380,169,13,13,28},
{380,182,13,13,27},
{380,195,26,13,30},
{380,221,12,13,27},
{380,233,13,13,30},
{380,246,13,13,27},
{380,259,13,13,22},
{380,272,13,13,18},
{380,285,26,13,22},
{380,311,13,13,30},
{380,324,13,13,29},
{380,337,13,13,20},
{380,350,13,13,23},
{380,363,13,13,20},
{380,376,13,13,25},
{380,389,13,13,20},
{380,402,13,13,17},
{380,415,13,13,12},
{380,441,26,13,4},
{380,467,13,13,7},
{380,480,13,13,1},
{380,493,13,13,25},
{380,506,13,13,19},
{380,519,26,13,15},
{380,545,39,13,5},
{380,584,26,13,4},
{380,610,13,13,12},
{380,623,13,13,31},
{380,636,13,13,25},
{380,649,13,13,2},
{380,662,13,13,12},
{380,675,13,13,25},
{380,688,12,13,28},
{380,726,13,13,25},
{380,739,13,13,15},
{380,778,13,13,23},
{380,791,26,13,30},
{380,843,13,13,15},
{380,856,13,13,13},
{380,882,13,13,2},
{367,765,13,39,2},
{367,830,13,39,1},
{380,39,13,26,15},
{380,428,13,26,7},
{380,700,13,26,19},
{380,713,13,26,8},
{380,752,13,26,6},
{380,869,13,26,15},
{393,0,26,13,4},
{393,26,13,13,1},
{393,52,13,13,12},
{393,65,13,13,4},
{393,78,13,13,2},
{393,91,13,13,19},
{393,104,13,13,29},
{393,117,13,13,14},
{393,130,13,13,8},
{393,143,13,13,19},
{393,169,13,13,24},
{393,182,13,13,28},
{393,195,13,13,24},
{393,208,13,13,31},
{393,221,12,13,30},
{393,233,26,13,28},
{393,259,13,13,27},
{393,272,13,13,30},
{393,285,13,13,27},
{393,298,13,13,18},
{393,311,13,13,27},
{393,324,13,13,32},
{393,337,13,13,31},
{393,350,13,13,20},
{393,363,13,13,17},
{393,376,13,13,10},
{393,389,13,13,13},
{393,402,26,13,17},
{393,493,13,13,15},
{393,506,13,13,9},
{393,519,26,13,1},
{393,545,39,13,4},
{393,584,13,13,7},
{393,597,13,13,1},
{393,610,26,13,31},
{393,649,26,13,6},
{393,675,13,13,15},
{393,688,12,13,26},
{393,726,13,13,13},
{393,739,13,13,12},
{393,778,13,13,19},
{393,791,13,13,27},
{393,804,13,13,30},
{393,817,13,13,23},
{393,843,13,13,12},
{393,856,13,13,14},
{393,156,13,26,23},
{393,441,52,26,4},
{393,882,13,26,7},
{406,0,39,13,4},
{406,39,13,13,7},
{406,52,13,13,15},
{406,65,13,13,6},
{406,78,13,13,4},
{406,91,13,13,6},
{406,104,13,13,28},
{406,117,13,13,20},
{406,130,26,13,6},
{406,169,13,13,22},
{406,182,26,13,30},
{406,208,13,13,22},
{406,221,12,13,31},
{406,233,26,13,30},
{406,259,13,13,22},
{406,272,13,13,24},
{406,285,26,13,30},
{406,311,13,13,25},
{406,324,13,13,28},
{406,337,13,13,32},
{406,350,13,13,31},
{406,363,26,13,25},
{406,389,13,13,14},
{406,402,26,13,8},
{406,428,13,13,6},
{406,493,13,13,1},
{406,506,13,13,2},
{406,519,52,13,4},
{406,571,13,13,7},
{406,584,13,13,1},
{406,597,13,13,29},
{406,610,13,13,31},
{406,675,13,13,1},
{406,688,12,13,19},
{406,700,13,13,20},
{406,713,13,13,2},
{406,726,13,13,7},
{406,739,13,13,6},
{406,752,13,13,4},
{406,765,13,13,6},
{406,778,13,13,17},
{406,791,13,13,18},
{406,817,13,13,16},
{406,830,13,13,6},
{406,843,13,13,11},
{406,856,13,13,15},
{406,869,13,13,14},
{393,636,13,39,20},
{406,623,13,26,29},
{406,804,13,26,28},
{419,0,52,13,4},
{419,52,13,13,13},
{419,65,13,13,10},
{419,78,13,13,8},
{419,91,13,13,2},
{419,104,13,13,19},
{419,117,13,13,26},
{419,130,13,13,6},
{419,156,13,13,11},
{419,169,13,13,23},
{419,182,13,13,27},
{419,195,13,13,31},
{419,208,13,13,27},
{419,221,12,13,24},
{419,233,13,13,30},
{419,246,13,13,31},
{419,259,13,13,30},
{419,272,13,13,21},
{419,285,13,13,16},
{419,298,13,13,27},
{419,311,13,13,30},
{419,324,13,13,29},
{419,337,13,13,28},
{419,350,13,13,32},
{419,363,13,13,31},
{419,376,13,13,23},
{419,389,13,13,19},
{419,402,13,13,13},
{419,415,13,13,14},
{419,428,13,13,15},
{419,441,13,13,11},
{419,454,104,13,4},
{419,558,13,13,7},
{419,571,13,13,1},
{419,584,13,13,29},
{419,597,13,13,32},
{419,688,12,13,11},
{419,700,13,13,17},
{419,713,39,13,4},
{419,752,13,13,1},
{419,765,13,13,12},
{419,778,26,13,15},
{419,817,13,13,13},
{419,830,13,13,9},
{419,869,13,13,10},
{419,882,13,13,3},
{406,649,13,39,1},
{406,662,13,39,7},
{419,610,13,26,25},
{432,0,65,13,4},
{432,65,13,13,11},
{432,78,39,13,8},
{432,117,13,13,23},
{432,130,13,13,17},
{432,169,13,13,13},
{432,182,13,13,25},
{432,195,13,13,29},
{432,208,13,13,25},
{432,221,12,13,16},
{432,233,13,13,27},
{432,246,13,13,30},
{432,259,26,13,31},
{432,285,13,13,24},
{432,298,13,13,18},
{432,311,13,13,22},
{432,324,13,13,28},
{432,337,13,13,29},
{432,350,13,13,28},
{432,363,26,13,32},
{432,389,13,13,29},
{432,402,13,13,14},
{432,415,13,13,8},
{432,428,39,13,2},
{432,467,52,13,7},
{432,519,26,13,4},
{432,545,13,13,7},
{432,558,13,13,1},
{432,571,13,13,20},
{432,584,13,13,31},
{432,597,13,13,29},
{432,623,13,13,28},
{432,636,13,13,23},
{432,688,12,13,8},
{432,700,13,13,9},
{432,713,26,13,5},
{432,739,26,13,4},
{432,765,26,13,6},
{432,791,13,13,17},
{432,804,13,13,25},
{432,830,13,13,10},
{341,895,26,117,4},
{419,143,13,39,8},
{419,675,13,39,4},
{419,843,13,39,8},
{419,856,13,39,17},
{432,156,13,26,10},
{432,817,13,26,6},
{432,869,13,26,11},
{432,882,13,26,1},
{445,78,13,13,11},
{445,91,13,13,9},
{445,104,13,13,2},
{445,117,13,13,19},
{445,130,13,13,20},
{445,169,13,13,8},
{445,182,13,13,14},
{445,195,13,13,28},
{445,208,13,13,19},
{445,221,12,13,15},
{445,233,13,13,21},
{445,246,13,13,24},
{445,259,13,13,28},
{445,272,26,13,31},
{445,298,13,13,27},
{445,311,26,13,22},
{445,337,39,13,27},
{445,376,13,13,30},
{445,389,26,13,31},
{445,415,13,13,29},
{445,428,13,13,25},
{445,441,13,13,15},
{445,454,13,13,7},
{445,467,65,13,1},
{445,532,13,13,7},
{445,545,13,13,1},
{445,558,13,13,18},
{445,571,13,13,31},
{445,584,13,13,29},
{445,597,13,13,26},
{445,610,39,13,25},
{445,649,13,13,15},
{445,662,13,13,2},
{445,688,12,13,6},
{445,700,13,13,4},
{445,713,13,13,5},
{445,726,52,13,4},
{445,778,13,13,1},
{445,791,26,13,19},
{445,830,13,13,13},
{445,0,78,27,4},
{458,78,13,14,9},
{458,91,13,14,6},
{458,104,13,14,4},
{458,117,13,14,12},
{458,130,13,14,25},
{458,143,13,14,17},
{458,156,39,14,8},
{458,195,13,14,25},
{458,208,13,14,26},
{458,221,12,14,10},
{458,233,13,14,19},
{458,246,13,14,22},
{458,259,13,14,24},
{458,272,13,14,28},
{458,285,26,14,31},
{458,311,13,14,30},
{458,324,13,14,24},
{458,337,13,14,22},
{458,350,13,14,24},
{458,363,13,14,27},
{458,376,13,14,28},
{458,389,13,14,30},
{458,428,52,14,29},
{458,480,13,14,26},
{458,493,13,14,25},
{458,506,13,14,19},
{458,519,13,14,12},
{458,532,13,14,4},
{458,545,13,14,15},
{458,558,13,14,31},
{458,571,13,14,29},
{458,584,13,14,26},
{458,597,13,14,20},
{458,623,13,14,19},
{458,636,26,14,17},
{458,662,13,14,7},
{458,778,13,14,11},
{458,791,13,14,19},
{458,804,13,14,9},
{458,817,13,14,8},
{458,830,26,14,9},
{458,856,13,14,13},
{458,869,13,14,7},
{458,882,39,14,4},
{458,402,26,27,31},
{458,610,13,27,25},
{458,675,103,27,4},
{472,0,117,13,4},
{472,117,13,13,1},
{472,130,13,13,15},
{472,143,13,13,20},
{472,169,13,13,8},
{472,182,13,13,1},
{472,195,13,13,19},
{472,208,13,13,28},
{472,221,12,13,13},
{472,233,13,13,11},
{472,246,26,13,25},
{472,272,13,13,23},
{472,285,13,13,22},
{472,298,13,13,28},
{472,311,26,13,31},
{472,337,13,13,29},
{472,350,26,13,24},
{472,376,13,13,27},
{472,389,13,13,28},
{472,428,13,13,26},
{472,441,65,13,29},
{472,506,52,13,31},
{472,558,13,13,29},
{472,571,13,13,26},
{472,584,13,13,25},
{472,597,13,13,13},
{472,623,13,13,17},
{472,636,13,13,10},
{472,649,13,13,8},
{472,662,13,13,9},
{472,778,13,13,12},
{472,791,13,13,11},
{472,804,13,13,2},
{472,817,13,13,6},
{472,830,39,13,9},
{472,156,13,26,15},
{485,130,13,13,2},
{485,143,13,13,14},
{485,169,13,13,10},
{485,182,13,13,9},
{485,195,13,13,8},
{485,208,13,13,25},
{485,221,12,13,23},
{485,233,13,13,6},
{485,246,13,13,13},
{485,259,26,13,25},
{485,285,13,13,16},
{485,298,13,13,17},
{485,311,13,13,27},
{485,324,39,13,31},
{485,363,13,13,27},
{485,376,26,13,24},
{485,402,13,13,30},
{485,415,13,13,31},
{485,428,26,13,29},
{485,454,130,13,26},
{485,584,13,13,19},
{485,597,13,13,6},
{485,610,13,13,17},
{485,623,13,13,20},
{485,636,13,13,2},
{485,649,13,13,6},
{485,662,116,13,4},
{485,778,13,13,2},
{485,791,13,13,4},
{485,817,13,13,8},
{485,830,13,13,10},
{485,843,13,13,8},
{485,856,13,13,6},
{472,869,52,39,4},
{485,0,130,26,4},
{485,804,13,26,6},
{498,130,13,13,7},
{498,143,13,13,4},
{498,156,13,13,11},
{498,169,26,13,10},
{498,208,13,13,14},
{498,221,12,13,26},
{498,233,13,13,10},
{498,246,13,13,8},
{498,259,13,13,12},
{498,272,13,13,25},
{498,285,13,13,23},
{498,298,13,13,8},
{498,311,13,13,14},
{498,324,13,13,28},
{498,337,39,13,31},
{498,376,13,13,30},
{498,389,13,13,28},
{498,402,13,13,24},
{498,415,13,13,29},
{498,428,13,13,30},
{498,441,143,13,26},
{498,584,13,13,17},
{498,597,13,13,3},
{498,610,13,13,7},
{498,623,13,13,15},
{498,636,13,13,7},
{498,649,155,13,4},
{498,817,26,13,8},
{498,843,26,13,6},
{498,195,13,26,6},
{511,0,156,13,4},
{511,156,26,13,9},
{511,182,13,13,8},
{511,208,13,13,1},
{511,221,25,13,20},
{511,246,26,13,6},
{511,272,13,13,12},
{511,285,13,13,25},
{511,298,13,13,17},
{511,311,13,13,8},
{511,324,13,13,17},
{511,337,13,13,28},
{511,350,52,13,31},
{511,402,13,13,30},
{511,415,13,13,28},
{511,428,26,13,29},
{511,454,130,13,26},
{511,610,13,13,4},
{511,623,13,13,1},
{511,636,285,13,4},
{524,52,13,13,6},
{524,91,52,13,4},
{524,143,13,13,1},
{524,156,13,13,2},
{524,169,13,13,6},
{524,182,26,13,13},
{524,208,13,13,9},
{524,221,12,13,6},
{524,233,13,13,17},
{524,246,13,13,2},
{524,259,13,13,7},
{524,272,13,13,1},
{524,285,13,13,12},
{524,298,13,13,20},
{524,311,39,13,11},
{524,350,13,13,29},
{524,363,26,13,31},
{524,389,13,13,30},
{524,402,39,13,31},
{524,441,13,13,30},
{524,454,13,13,29},
{524,467,26,13,20},
{524,493,52,13,25},
{524,545,39,13,26},
{524,610,311,26,4},
{537,91,26,13,4},
{537,117,26,13,1},
{537,143,13,13,12},
{537,156,13,13,15},
{537,169,13,13,12},
{537,182,13,13,19},
{537,195,13,13,25},
{537,208,13,13,20},
{537,221,12,13,19},
{537,233,13,13,20},
{537,246,13,13,15},
{537,259,39,13,1},
{537,298,26,13,13},
{537,324,13,13,10},
{537,350,13,13,8},
{537,363,13,13,26},
{537,376,39,13,30},
{537,415,13,13,29},
{537,428,39,13,31},
{537,467,13,13,30},
{537,480,26,13,20},
{537,506,39,13,25},
{537,545,13,13,26},
{537,558,13,13,25},
{511,597,13,52,1},
{524,0,39,39,4},
{524,39,13,39,5},
{524,65,26,39,5},
{537,52,13,26,8},
{537,337,13,26,11},
{537,571,13,26,29},
{550,91,13,13,4},
{550,104,13,13,1},
{550,117,13,13,7},
{550,130,13,13,18},
{550,143,13,13,21},
{550,156,13,13,18},
{550,169,39,13,8},
{550,208,13,13,9},
{550,221,12,13,13},
{550,233,13,13,25},
{550,246,13,13,28},
{550,259,13,13,25},
{550,272,13,13,20},
{550,285,13,13,19},
{550,298,13,13,17},
{550,311,13,13,13},
{550,324,13,13,2},
{550,350,13,13,20},
{550,363,26,13,28},
{550,389,13,13,31},
{550,415,13,13,14},
{550,428,13,13,17},
{550,441,13,13,26},
{550,454,39,13,31},
{550,519,13,13,25},
{550,532,13,13,20},
{550,545,13,13,25},
{550,558,13,13,26},
{550,610,52,13,4},
{550,662,26,13,7},
{550,688,233,13,4},
{511,584,13,65,15},
{550,402,13,26,25},
{550,493,13,26,29},
{550,506,13,26,26},
{563,91,13,13,3},
{563,104,13,13,4},
{563,117,13,13,18},
{563,130,13,13,21},
{563,143,26,13,15},
{563,195,13,13,6},
{563,208,25,13,8},
{563,233,13,13,6},
{563,246,13,13,15},
{563,259,39,13,23},
{563,298,13,13,25},
{563,311,13,13,29},
{563,324,13,13,31},
{563,337,13,13,29},
{563,350,13,13,28},
{563,363,13,13,27},
{563,376,13,13,28},
{563,389,13,13,30},
{563,415,39,13,14},
{563,454,13,13,10},
{563,467,13,13,17},
{563,480,13,13,25},
{563,571,13,13,31},
{563,597,13,13,4},
{563,610,13,13,7},
{563,623,26,13,4},
{563,649,13,13,7},
{563,662,38,13,1},
{563,700,221,13,4},
{563,0,91,26,4},
{563,169,26,26,10},
{563,519,52,26,20},
{576,91,13,13,7},
{576,117,26,13,18},
{576,156,13,13,15},
{576,195,26,13,6},
{576,221,25,13,9},
{576,246,13,13,8},
{576,259,13,13,13},
{576,272,13,13,18},
{576,285,26,13,16},
{576,311,13,13,21},
{576,324,26,13,30},
{576,350,13,13,18},
{576,363,39,13,21},
{576,402,26,13,26},
{576,428,13,13,17},
{576,441,13,13,14},
{576,454,13,13,13},
{576,467,26,13,10},
{576,493,13,13,8},
{576,506,13,13,17},
{576,571,13,13,29},
{576,584,13,13,26},
{576,597,13,13,1},
{576,610,13,13,5},
{576,623,13,13,7},
{576,636,26,13,1},
{576,662,13,13,23},
{576,688,12,13,12},
{576,700,13,13,1},
{576,713,208,13,4},
{576,104,13,27,17},
{576,675,13,27,25},
{589,0,78,14,4},
{589,78,13,14,1},
{589,91,13,14,23},
{589,117,26,14,15},
{589,156,26,14,10},
{589,182,13,14,9},
{589,195,13,14,6},
{589,208,13,14,4},
{589,221,12,14,11},
{589,233,13,14,9},
{589,246,13,14,6},
{589,259,13,14,9},
{589,272,13,14,13},
{589,285,26,14,12},
{589,311,13,14,16},
{589,324,13,14,12},
{589,337,13,14,28},
{589,363,13,14,11},
{589,389,13,14,18},
{589,415,13,14,19},
{589,428,13,14,23},
{589,454,13,14,14},
{589,467,39,14,10},
{589,506,13,14,13},
{589,519,26,14,17},
{589,545,39,14,20},
{589,584,13,14,29},
{589,610,13,14,11},
{589,623,13,14,1},
{589,636,13,14,12},
{589,649,13,14,29},
{589,662,13,14,31},
{589,688,12,14,23},
{589,700,13,14,19},
{589,713,13,14,1},
{589,726,13,14,4},
{589,739,13,14,7},
{589,752,78,14,4},
{589,830,13,14,9},
{589,843,13,14,7},
{589,856,65,14,4},
{589,350,13,27,29},
{589,376,13,27,16},
{589,402,13,27,15},
{589,441,13,27,20},
{589,597,13,27,26},
{603,0,65,13,4},
{603,78,13,13,15},
{603,91,13,13,28},
{603,104,13,13,6},
{603,117,13,13,14},
{603,130,13,13,10},
{603,156,13,13,10},
{603,182,13,13,6},
{603,195,13,13,4},
{603,208,13,13,1},
{603,221,12,13,13},
{603,233,13,13,14},
{603,246,13,13,2},
{603,259,26,13,6},
{603,285,13,13,7},
{603,298,13,13,1},
{603,311,13,13,7},
{603,324,13,13,18},
{603,363,13,13,30},
{603,415,13,13,8},
{603,454,13,13,26},
{603,467,13,13,20},
{603,480,26,13,14},
{603,506,13,13,10},
{603,519,13,13,14},
{603,532,13,13,17},
{603,545,13,13,19},
{603,558,39,13,20},
{603,610,26,13,29},
{603,636,26,13,31},
{603,662,13,13,27},
{603,675,13,13,18},
{603,688,12,13,16},
{603,700,26,13,19},
{603,726,13,13,11},
{603,739,39,13,1},
{603,778,13,13,7},
{603,791,130,13,4},
{576,143,13,53,8},
{603,65,13,26,1},
{603,169,13,26,8},
{603,337,13,26,16},
{603,389,13,26,21},
{616,52,13,13,7},
{616,78,13,13,25},
{616,91,13,13,20},
{616,104,13,13,2},
{616,117,26,13,10},
{616,156,13,13,9},
{616,182,26,13,4},
{616,208,13,13,2},
{616,221,12,13,11},
{616,233,13,13,19},
{616,246,78,13,4},
{616,324,13,13,7},
{616,350,13,13,19},
{616,363,13,13,28},
{616,376,13,13,27},
{616,402,13,13,18},
{616,415,13,13,11},
{616,441,13,13,14},
{616,454,13,13,20},
{616,467,39,13,25},
{616,506,13,13,19},
{616,519,39,13,17},
{616,558,13,13,19},
{616,571,52,13,20},
{616,636,13,13,31},
{616,649,13,13,27},
{616,662,13,13,22},
{616,675,13,13,24},
{616,688,12,13,22},
{616,700,13,13,12},
{616,713,13,13,15},
{616,726,13,13,25},
{616,739,13,13,21},
{616,752,13,13,15},
{616,765,13,13,7},
{616,778,26,13,1},
{616,804,13,13,4},
{616,817,13,13,7},
{616,830,91,13,4},
{603,428,13,39,10},
{616,0,52,26,4},
{616,623,13,26,29},
{629,65,13,13,15},
{629,78,13,13,26},
{629,91,13,13,13},
{629,130,13,13,15},
{629,143,13,13,13},
{629,169,13,13,9},
{629,182,39,13,4},
{629,221,12,13,6},
{629,233,13,13,17},
{629,246,13,13,14},
{629,259,13,13,6},
{629,272,13,13,9},
{629,285,13,13,6},
{629,298,39,13,4},
{629,337,13,13,6},
{629,350,13,13,15},
{629,363,13,13,21},
{629,376,13,13,25},
{629,389,13,13,22},
{629,402,13,13,16},
{629,415,13,13,17},
{629,441,13,13,13},
{629,454,13,13,17},
{629,467,13,13,19},
{629,480,13,13,26},
{629,493,26,13,29},
{629,519,13,13,25},
{629,532,26,13,17},
{629,558,13,13,20},
{629,571,52,13,26},
{629,636,13,13,25},
{629,649,51,13,24},
{629,700,13,13,22},
{629,713,13,13,12},
{629,726,13,13,23},
{629,739,13,13,28},
{629,765,13,13,31},
{629,778,13,13,29},
{629,791,13,13,15},
{629,804,13,13,6},
{629,817,26,13,1},
{629,843,13,13,4},
{629,856,26,13,7},
{629,882,39,13,4},
{629,52,13,26,1},
{629,104,13,26,9},
{629,156,13,26,8},
{629,752,13,26,24},
{642,0,39,13,4},
{642,39,13,13,7},
{642,65,13,13,28},
{642,78,13,13,25},
{642,91,13,13,8},
{642,130,26,13,15},
{642,169,13,13,6},
{642,182,26,13,4},
{642,208,13,13,6},
{642,221,12,13,2},
{642,233,13,13,15},
{642,246,13,13,17},
{642,259,13,13,8},
{642,298,13,13,6},
{642,311,26,13,4},
{642,337,13,13,7},
{642,350,13,13,6},
{642,363,13,13,12},
{642,376,13,13,21},
{642,389,13,13,25},
{642,402,13,13,18},
{642,415,13,13,13},
{642,428,13,13,17},
{642,441,13,13,8},
{642,454,13,13,10},
{642,467,13,13,17},
{642,480,13,13,19},
{642,493,13,13,23},
{642,506,13,13,28},
{642,519,26,13,29},
{642,545,13,13,26},
{642,558,39,13,20},
{642,597,13,13,26},
{642,610,13,13,29},
{642,623,13,13,25},
{642,636,64,13,24},
{642,700,13,13,27},
{642,713,13,13,24},
{642,726,26,13,28},
{642,765,13,13,22},
{642,778,26,13,31},
{642,804,26,13,23},
{642,830,13,13,17},
{642,843,13,13,7},
{642,856,26,13,1},
{642,882,13,13,4},
{642,895,13,13,7},
{642,908,13,13,4},
{629,117,13,39,8},
{642,272,26,26,9},
{655,52,13,13,19},
{655,65,13,13,31},
{655,78,13,13,21},
{655,91,13,13,17},
{655,104,13,13,13},
{655,130,13,13,15},
{655,143,13,13,17},
{655,156,13,13,6},
{655,169,26,13,4},
{655,233,13,13,11},
{655,246,13,13,19},
{655,259,13,13,13},
{655,298,13,13,8},
{655,311,39,13,4},
{655,350,13,13,7},
{655,363,13,13,2},
{655,376,13,13,11},
{655,389,13,13,21},
{655,402,13,13,25},
{655,415,13,13,12},
{655,428,13,13,15},
{655,441,13,13,19},
{655,454,13,13,15},
{655,467,13,13,8},
{655,480,13,13,15},
{655,493,13,13,19},
{655,506,13,13,23},
{655,519,13,13,22},
{655,532,13,13,23},
{655,545,13,13,28},
{655,558,13,13,29},
{655,571,26,13,26},
{655,597,13,13,29},
{655,610,13,13,25},
{655,623,77,13,24},
{655,726,13,13,24},
{655,739,13,13,27},
{655,765,13,13,24},
{655,778,13,13,21},
{655,791,13,13,31},
{655,804,13,13,30},
{655,817,13,13,23},
{655,830,13,13,27},
{655,843,13,13,28},
{655,869,13,13,19},
{655,882,26,13,1},
{655,908,13,13,7},
{655,26,13,26,7},
{655,39,13,26,1},
{655,221,12,26,4},
{655,713,13,26,27},
{655,752,13,26,30},
{655,856,13,26,25},
{668,52,13,13,30},
{668,65,13,13,28},
{668,91,13,13,15},
{668,104,13,13,12},
{668,117,13,13,11},
{668,130,13,13,13},
{668,143,13,13,20},
{668,156,13,13,11},
{668,169,13,13,1},
{668,182,13,13,4},
{668,233,13,13,2},
{668,246,26,13,17},
{668,272,13,13,8},
{668,285,26,13,9},
{668,311,13,13,6},
{668,324,52,13,4},
{668,376,13,13,1},
{668,389,13,13,7},
{668,402,13,13,21},
{668,415,13,13,23},
{668,428,26,13,11},
{668,454,13,13,19},
{668,467,13,13,25},
{668,480,13,13,13},
{668,493,13,13,11},
{668,506,13,13,17},
{668,519,13,13,21},
{668,532,26,13,18},
{668,558,13,13,22},
{668,571,13,13,27},
{668,584,13,13,28},
{668,597,13,13,25},
{668,610,90,13,24},
{668,765,13,13,28},
{668,778,26,13,24},
{668,804,13,13,31},
{668,830,13,13,22},
{668,843,13,13,16},
{668,869,13,13,28},
{668,882,13,13,29},
{668,895,13,13,19},
{668,908,13,13,1},
{655,0,26,39,4},
{668,78,13,26,22},
{668,726,26,26,24},
{668,817,13,26,30},
{681,39,13,13,17},
{681,65,13,13,18},
{681,91,13,13,12},
{681,104,13,13,8},
{681,117,13,13,10},
{681,130,13,13,11},
{681,143,13,13,19},
{681,156,13,13,15},
{681,169,13,13,6},
{681,182,13,13,7},
{681,221,12,13,9},
{681,233,13,13,6},
{681,246,13,13,13},
{681,272,13,13,11},
{681,298,13,13,11},
{681,311,13,13,10},
{681,324,13,13,6},
{681,337,52,13,4},
{681,389,13,13,1},
{681,402,13,13,4},
{681,415,13,13,19},
{681,428,13,13,20},
{681,441,13,13,7},
{681,454,13,13,1},
{681,467,13,13,20},
{681,480,13,13,26},
{681,493,13,13,13},
{681,506,13,13,10},
{681,519,13,13,16},
{681,532,39,13,21},
{681,571,13,13,22},
{681,584,13,13,21},
{681,597,91,13,24},
{681,688,12,13,27},
{681,752,13,13,27},
{681,765,13,13,30},
{681,778,13,13,27},
{681,791,13,13,24},
{681,804,13,13,27},
{681,830,13,13,31},
{681,843,13,13,28},
{681,856,13,13,16},
{681,869,13,13,18},
{681,882,13,13,22},
{681,895,13,13,30},
{681,908,13,13,23},
{655,195,26,52,6},
{655,700,13,52,30},
{681,52,13,26,31},
{681,259,13,26,19},
{681,713,13,26,28},
{694,39,13,13,29},
{694,65,13,13,16},
{694,78,13,13,21},
{694,104,13,13,6},
{694,117,13,13,9},
{694,130,13,13,8},
{694,143,13,13,18},
{694,156,13,13,17},
{694,169,13,13,8},
{694,182,13,13,9},
{694,221,25,13,9},
{694,246,13,13,11},
{694,272,13,13,17},
{694,298,13,13,12},
{694,311,13,13,13},
{694,324,13,13,10},
{694,337,78,13,4},
{694,415,13,13,6},
{694,428,13,13,17},
{694,441,13,13,19},
{694,454,13,13,11},
{694,467,13,13,1},
{694,480,13,13,20},
{694,493,13,13,28},
{694,506,13,13,17},
{694,519,13,13,11},
{694,532,13,13,18},
{694,545,39,13,21},
{694,584,13,13,22},
{694,597,52,13,24},
{694,649,13,13,28},
{694,662,26,13,27},
{694,726,39,13,24},
{694,765,26,13,27},
{694,791,26,13,24},
{694,817,13,13,27},
{694,830,13,13,28},
{694,843,13,13,30},
{694,869,13,13,22},
{694,882,13,13,16},
{694,895,13,13,18},
{694,908,13,13,31},
{681,26,13,39,1},
{681,285,13,39,8},
{694,13,13,26,7},
{694,91,13,26,19},
{694,688,12,26,24},
{694,856,13,26,28},
{707,39,13,13,31},
{707,52,13,13,30},
{707,65,13,13,12},
{707,78,13,13,16},
{707,104,13,13,8},
{707,117,13,13,6},
{707,130,13,13,2},
{707,143,13,13,15},
{707,156,13,13,18},
{707,169,26,13,10},
{707,195,13,13,8},
{707,208,13,13,3},
{707,221,12,13,8},
{707,259,13,13,18},
{707,272,13,13,19},
{707,311,13,13,12},
{707,324,13,13,13},
{707,337,13,13,6},
{707,350,78,13,4},
{707,428,13,13,1},
{707,441,13,13,12},
{707,454,26,13,11},
{707,480,13,13,8},
{707,493,13,13,26},
{707,506,13,13,28},
{707,519,13,13,13},
{707,532,13,13,12},
{707,545,13,13,16},
{707,558,26,13,21},
{707,584,26,13,24},
{707,610,26,13,27},
{707,636,26,13,28},
{707,662,13,13,24},
{707,700,13,13,28},
{707,726,130,13,24},
{707,869,13,13,27},
{707,882,13,13,22},
{707,895,13,13,16},
{707,908,13,13,23},
{694,0,13,40,4},
{707,233,13,27,9},
{720,26,13,14,12},
{720,39,13,14,32},
{720,52,13,14,24},
{720,65,13,14,16},
{720,78,13,14,12},
{720,91,13,14,15},
{720,117,13,14,4},
{720,130,13,14,1},
{720,143,13,14,12},
{720,156,13,14,21},
{720,169,13,14,12},
{720,182,26,14,9},
{720,208,25,14,8},
{720,259,13,14,15},
{720,272,13,14,21},
{720,285,13,14,15},
{720,337,13,14,11},
{720,350,65,14,4},
{720,415,13,14,6},
{720,428,13,14,7},
{720,441,13,14,1},
{720,454,13,14,8},
{720,467,13,14,9},
{720,480,13,14,6},
{720,493,13,14,13},
{720,506,13,14,26},
{720,519,13,14,23},
{720,532,26,14,13},
{720,558,13,14,16},
{720,571,13,14,22},
{720,584,13,14,27},
{720,597,39,14,28},
{720,636,13,14,27},
{720,649,26,14,24},
{720,688,25,14,24},
{720,804,13,14,18},
{720,817,13,14,21},
{720,830,65,14,24},
{720,895,13,14,22},
{707,246,13,40,8},
{707,298,13,40,11},
{707,675,13,40,27},
{720,104,13,27,9},
{720,311,26,27,12},
{720,726,78,27,24},
{734,26,13,13,28},
{734,39,13,13,31},
{734,52,13,13,16},
{734,78,13,13,7},
{734,91,13,13,8},
{734,156,13,13,19},
{734,169,13,13,17},
{734,182,39,13,8},
{734,221,25,13,10},
{734,259,13,13,11},
{734,272,13,13,23},
{734,285,13,13,19},
{734,337,13,13,13},
{734,350,13,13,8},
{734,363,26,13,4},
{734,389,13,13,7},
{734,402,26,13,8},
{734,428,13,13,6},
{734,441,13,13,4},
{734,454,13,13,7},
{734,480,13,13,4},
{734,493,13,13,1},
{734,506,13,13,15},
{734,519,13,13,25},
{734,532,13,13,19},
{734,545,13,13,13},
{734,558,13,13,12},
{734,571,13,13,18},
{734,584,39,13,24},
{734,623,26,13,27},
{734,688,12,13,24},
{734,700,13,13,21},
{734,804,13,13,21},
{734,817,13,13,18},
{734,830,39,13,22},
{734,869,13,13,21},
{707,713,13,53,30},
{720,13,13,40,1},
{734,0,13,26,7},
{734,117,26,26,4},
{734,143,13,26,1},
{734,467,13,26,6},
{734,649,26,26,22},
{734,882,13,26,24},
{734,895,13,26,27},
{747,39,13,13,28},
{747,52,13,13,12},
{747,104,13,13,8},
{747,156,13,13,15},
{747,169,13,13,19},
{747,182,13,13,8},
{747,195,26,13,6},
{747,221,12,13,9},
{747,233,26,13,13},
{747,259,13,13,8},
{747,272,13,13,21},
{747,285,13,13,25},
{747,298,52,13,12},
{747,350,13,13,10},
{747,376,52,13,4},
{747,428,13,13,8},
{747,441,26,13,7},
{747,480,26,13,4},
{747,506,13,13,1},
{747,519,26,13,20},
{747,545,13,13,10},
{747,558,13,13,15},
{747,571,13,13,16},
{747,584,13,13,21},
{747,597,26,13,24},
{747,623,13,13,27},
{747,636,13,13,24},
{747,700,13,13,16},
{747,778,13,13,22},
{747,791,26,13,24},
{747,817,26,13,18},
{747,843,13,13,22},
{747,856,26,13,21},
{720,908,13,53,16},
{747,78,13,26,8},
{747,91,13,26,6},
{747,675,13,26,24},
{747,726,52,26,24},
{760,13,13,13,19},
{760,39,13,13,18},
{760,104,13,13,4},
{760,117,13,13,6},
{760,130,26,13,4},
{760,156,13,13,7},
{760,169,13,13,20},
{760,182,13,13,11},
{760,195,13,13,6},
{760,208,13,13,9},
{760,221,25,13,8},
{760,246,13,13,17},
{760,259,26,13,14},
{760,298,13,13,17},
{760,337,13,13,15},
{760,350,13,13,11},
{760,376,130,13,4},
{760,506,13,13,5},
{760,519,13,13,4},
{760,532,13,13,23},
{760,545,13,13,17},
{760,558,13,13,2},
{760,571,13,13,12},
{760,584,13,13,16},
{760,597,13,13,21},
{760,610,26,13,27},
{760,636,13,13,22},
{760,649,13,13,24},
{760,662,13,13,22},
{760,713,13,13,28},
{760,817,13,13,23},
{760,830,13,13,18},
{760,843,13,13,24},
{760,856,26,13,22},
{760,882,26,13,24},
{734,65,13,52,18},
{747,26,13,39,31},
{747,363,13,39,9},
{747,688,12,39,27},
{760,0,13,26,1},
{760,52,13,26,16},
{760,285,13,26,28},
{760,311,13,26,8},
{760,778,39,26,22},
{773,13,13,13,30},
{773,39,13,13,12},
{773,91,26,13,4},
{773,117,13,13,7},
{773,143,13,13,4},
{773,169,26,13,19},
{773,195,13,13,2},
{773,208,25,13,10},
{773,233,13,13,8},
{773,246,13,13,13},
{773,259,13,13,25},
{773,272,13,13,18},
{773,298,13,13,25},
{773,350,13,13,13},
{773,376,13,13,6},
{773,519,13,13,1},
{773,532,13,13,12},
{773,545,13,13,23},
{773,558,13,13,12},
{773,584,13,13,11},
{773,597,13,13,16},
{773,610,13,13,22},
{773,623,13,13,27},
{773,636,52,13,22},
{773,713,13,13,25},
{773,739,39,13,24},
{773,817,13,13,25},
{773,830,13,13,22},
{773,869,13,13,22},
{773,895,13,13,23},
{773,908,13,13,18},
{760,324,13,39,12},
{760,700,13,39,12},
{773,78,13,26,6},
{773,130,13,26,11},
{773,156,13,26,1},
{773,337,13,26,16},
{773,389,130,26,4},
{773,571,13,26,6},
{773,726,13,26,27},
{773,843,26,26,24},
{773,882,13,26,24},
{786,13,13,13,31},
{786,26,13,13,24},
{786,39,13,13,7},
{786,52,26,13,18},
{786,91,39,13,4},
{786,143,13,13,7},
{786,169,13,13,12},
{786,182,13,13,25},
{786,195,13,13,8},
{786,208,13,13,10},
{786,221,12,13,13},
{786,233,13,13,9},
{786,246,13,13,8},
{786,259,13,13,17},
{786,272,13,13,26},
{786,285,26,13,28},
{786,311,13,13,11},
{786,350,13,13,15},
{786,363,13,13,8},
{786,376,13,13,7},
{786,519,13,13,5},
{786,532,13,13,1},
{786,545,13,13,19},
{786,558,13,13,23},
{786,584,13,13,9},
{786,597,13,13,11},
{786,610,13,13,16},
{786,623,13,13,22},
{786,636,13,13,24},
{786,649,39,13,22},
{786,688,12,13,24},
{786,713,13,13,21},
{786,739,13,13,22},
{786,752,13,13,24},
{786,765,52,13,22},
{786,817,13,13,24},
{786,830,13,13,27},
{786,869,13,13,21},
{786,895,13,13,25},
}

-- ============================================================
-- 主构建
-- ============================================================
BuildMenu = function()
    if menuBuilt and bgPanel and IsValidUI(bgPanel) then
        -- 已经构建过，走打开动画
        _G.U5AnimateMenuOpen()
        return
    end
    local canvas = GetCanvas()
    if not canvas then return end

    -- 首次构建自动居中
    if not _G.U5UIState.autoCentered then
        _G.U5UIState.autoCentered = true
        pcall(function()
            local vpX, vpY = 1920, 1080
            local ui_util = require("client.common.ui_util")
            if ui_util and ui_util.GetViewportSize then
                local vp = ui_util.GetViewportSize()
                if vp and vp.X and vp.X > 100 then vpX = vp.X; vpY = vp.Y end
            end
            if vpX <= 100 then
                local WLL = import("WidgetLayoutLibrary")
                if WLL and WLL.GetViewportSize then
                    local sz = WLL.GetViewportSize(
                        slua_GameFrontendHUD:GetPlayerController())
                    if sz and sz.X and sz.X > 100 then vpX = sz.X; vpY = sz.Y end
                end
            end
            -- v5.4：按"图片1"排版比例自适应（约 66.5% x 74% 视口）
            M_W = math.max(860, math.min(1900, math.floor(vpX * 0.665)))
            M_H = math.max(560, math.min(1200, math.floor(vpY * 0.740)))
            menuX = math.max(10, math.floor((vpX - M_W) * 0.5))
            menuY = math.max(10, math.floor((vpY - M_H) * 0.5))
        end)
    end

    pulseWidgets = {}
    rgbWidgets = {}
    allWidgets = {}
    dataDots = {}

    pcall(function()
        bgPanel = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", canvas)
        if bgPanel and slua.isValid(bgPanel) then
            local slot = canvas:AddChildToCanvas(bgPanel)
            if slot then
                slot:SetAutoSize(false)
                slot:SetZOrder(10000)
                slot:SetAnchors(FAnchors(0, 0, 0, 0))
                slot:SetAlignment(FVector2D(0, 0))
                slot:SetPosition(FVector2D(menuX, menuY))
                slot:SetSize(FVector2D(M_W, M_H))
            end
        end
    end)
    if not bgPanel or not slua.isValid(bgPanel) then return end

    -- ============================================================
    -- v5.4 毛玻璃双面板 + 插画背景（参照"图片1"排版：左窄右宽，居中大幅面）
    -- ============================================================
    local U5GAP = math.max(8, math.floor(M_W * U5_GAP_FRAC))
    local leftW = math.floor((M_W - U5GAP) * U5_LEFT_FRAC)
    LEFT_TAB_W = leftW
    local HX = leftW + U5GAP
    local rightW = M_W - HX
    local HCX = HX + rightW * 0.5
    _G._U5_BgPanelStrips = {}

    do
        local d = _G.U5ArtDesign
        local pal = _G.U5ArtPal or {}
        local cached = {}
        for i = 1, #pal do
            cached[i] = FLinearColor(pal[i][1], pal[i][2], pal[i][3], U5_ART_ALPHA)
        end
        local baseCol = FLinearColor(0.965, 0.975, 0.990, 0.82)

        local function DrawPanelList(list, ox, sx, sy)
            if not list then return end
            for i = 1, #list do
                local r = list[i]
                local x, y = ox + r[2] * sx, r[1] * sy
                local w, h = r[3] * sx, r[4] * sy
                if r[5] == 500 then
                    local b = Layer(bgPanel, x, y, w, h, baseCol, 0)
                    table.insert(_G._U5_BgPanelStrips, b)
                else
                    local col = cached[r[5]]
                    if col then Layer(bgPanel, x, y, w, h, col, 1) end
                end
            end
        end

        if d then
            DrawPanelList(_G.U5ArtL, 0, leftW / d.LW, M_H / d.H)
            DrawPanelList(_G.U5ArtR, HX, rightW / d.RW, M_H / d.H)
        end
    end

    -- 顶栏（v5.4 轻主题：强调色顶线 + 标题）
    Layer(bgPanel, HX + 30, 0, rightW - 60, 2, AccentColor(currentParentTab, 0.95),
        3, false, true, 1)

    Layer(bgPanel, HX + 16, HEADER_H*0.5 - 4, 8, 8,
        AccentColor(currentParentTab, 1.0), 30, false, true, 1)
    Text(bgPanel, "U5", HX + 34, HEADER_H*0.5, 18, C.text_bright, 2500, 0, 0.5)
    Text(bgPanel, _G.U5L("title"), HX + 82, HEADER_H*0.5, 11, C.text_dim,
        2500, 0, 0.5)

    _G._U5_CrumbText = Text(bgPanel, "● " .. _G.U5LTab(1),
        HCX, HEADER_H*0.5, 11, AccentDeep(currentParentTab),
        2500, 0.5, 0.5)

    -- 拖拽区
    local dragZone = MakeBtn(bgPanel, HX, 0, rightW, HEADER_H, 810, nil)
    if dragZone then
        pcall(function()
            if dragZone.OnPressed then
                dragZone.OnPressed:Add(function()
                    _G.U5UIState.dragActive = true
                    _G.U5UIState.dragMouseStart = nil
                end)
            end
            if dragZone.OnReleased then
                dragZone.OnReleased:Add(function()
                    _G.U5UIState.dragActive = false
                end)
            end
        end)
    end

    -- 搜索框
    local searchBox = nil
    pcall(function()
        searchBox = CGame:NewObjectFromPath("/Script/UMG.EditableTextBox", bgPanel)
    end)
    if searchBox and slua.isValid(searchBox) then
        pcall(function()
            searchBox:SetHintText(_G.U5L("searchHint"))
            searchBox:SetWidgetVisibility(UEnums.ESlateVisibility.Visible)
            local slot = bgPanel:AddChildToCanvas(searchBox)
            if slot then
                slot:SetAutoSize(false)
                slot:SetPosition(FVector2D(HCX + 20, HEADER_H*0.5 - 11))
                slot:SetSize(FVector2D(140, 22))
                slot:SetZOrder(2600)
            end
            if searchBox.OnTextChanged then
                searchBox.OnTextChanged:Add(function(text)
                    pcall(function()
                        _G.U5UIState.searchKeyword = tostring(text or ""):lower()
                        _G.ApplySearchFilter()
                    end)
                end)
            end
        end)
    end

    -- 全开 / 全关
    local function _bulkToggle(val)
        local p = currentParentTab
        local subs = _G.U5Rows[p] or {}
        for _, rows in pairs(subs) do
            for _, r in ipairs(rows) do
                if r.kind == "toggle" then
                    r.cfgTable[r.configKey] = val
                    if _G.ConfigAutoSave then
                        _G.ConfigAutoSave:MarkDirty(r.saveName)
                    end
                    if r.refresh then pcall(r.refresh) end
                end
            end
        end
    end
    local btnY = HEADER_H*0.5 - 9
    MakeBtn(bgPanel, HCX + 172, btnY, 40, 18, 2650, function() _bulkToggle(1) end)
    Text(bgPanel, _G.U5L("allOn"), HCX + 192, HEADER_H*0.5, 10,
        C.green, 2660, 0.5, 0.5)
    MakeBtn(bgPanel, HCX + 216, btnY, 40, 18, 2650, function() _bulkToggle(0) end)
    Text(bgPanel, _G.U5L("allOff"), HCX + 236, HEADER_H*0.5, 10,
        C.red, 2660, 0.5, 0.5)

    -- 预设 P1/P2/P3
    for i = 1, 3 do
        local px = M_W - 130 + (i-1) * 24
        local lastClick = 0
        MakeBtn(bgPanel, px, btnY, 22, 18, 2650, function()
            local now = os.clock()
            if now - lastClick < 0.4 then
                lastClick = 0
                _G.U5SaveProfile(i)
            else
                lastClick = now
                local myNow = now
                _G.U5Tween(0.35, 0, 1, function() end, function()
                    if lastClick == myNow then _G.U5LoadProfile(i) end
                end)
            end
        end)
        Text(bgPanel, "P"..i, px + 11, HEADER_H*0.5, 10,
            C.text_normal, 2660, 0.5, 0.5, true, true)
    end

    -- 语言
    MakeBtn(bgPanel, M_W - 76, btnY, 20, 18, 2650, function()
        _G.U5SetLanguage(_G.U5UIState.lang == "zh" and "en" or "zh")
    end)
    Text(bgPanel, "◎", M_W - 66, HEADER_H*0.5, 11,
        C.text_normal, 2660, 0.5, 0.5)

    -- 方向键
    local arrSize = 12
    local arrX = M_W - 52
    local arrY = HEADER_H*0.5 - arrSize - 3
    MakeArrowBtn(bgPanel, arrX, arrY, arrSize, "up", "▲")
    MakeArrowBtn(bgPanel, arrX - arrSize - 2, arrY + arrSize + 2, arrSize, "left", "◄")
    MakeArrowBtn(bgPanel, arrX + arrSize + 2, arrY + arrSize + 2, arrSize, "right", "►")
    MakeArrowBtn(bgPanel, arrX, arrY + (arrSize + 2) * 2, arrSize, "down", "▼")

    -- 长按 logo 切换背景
    do
        local headerClickCount, headerLastClick = 0, 0
        MakeBtn(bgPanel, 8, 0, 60, HEADER_H, 950, function()
            local now = os.clock()
            if now - headerLastClick > 0.6 then headerClickCount = 0 end
            headerLastClick = now
            headerClickCount = headerClickCount + 1
            if headerClickCount >= 5 then
                headerClickCount = 0
                _G.U5UIState.bgAlpha =
                    (_G.U5UIState.bgAlpha <= 0.75) and 0.82 or 0.68
                if _G._U5_BgPanelStrips then
                    pcall(function()
                        for _, sw2 in ipairs(_G._U5_BgPanelStrips) do
                            if sw2 and IsValidUI(sw2) then
                                sw2:SetBrushColor(FLinearColor(
                                    0.965, 0.975, 0.990,
                                    _G.U5UIState.bgAlpha))
                            end
                        end
                    end)
                end
            end
        end)
    end

    -- 关闭按钮 → 走关闭动画
    local closeSize = 22
    local closeX = M_W - closeSize - 10
    local closeY = HEADER_H * 0.5 - closeSize * 0.5
    Layer(bgPanel, closeX + 1, closeY + 1, closeSize, closeSize, C.shadow_deep, 5)
    Layer(bgPanel, closeX, closeY, closeSize, closeSize, C.border, 6)
    Layer(bgPanel, closeX + 1, closeY + 1, closeSize - 2, closeSize - 2,
        FLinearColor(0.99, 0.86, 0.88, 1.0), 7)
    Text(bgPanel, "✕", closeX + closeSize * 0.5, closeY + closeSize * 0.5,
        12, C.red, 400, 0.5, 0.5)
    MakeBtn(bgPanel, closeX, closeY, closeSize, closeSize, 970, function()
        isMenuOpen = false
        _G.U5AnimateMenuClose()
    end)

    -- 左侧主标签
    local sideY = HEADER_H
    local sideH = M_H - HEADER_H - FOOTER_H
        -- v5.4：左侧区域即圆角面板本体（无需额外底色）

    local pTabY = sideY + 10
    local pTabH = 54
    local pGap = 8
    for i = 1, NUM_PARENT_TABS do
        local ty = pTabY + (i - 1) * (pTabH + pGap)
        local isActive = (i == 1)

        local tbg = Layer(bgPanel, 14, ty, LEFT_TAB_W - 28, pTabH,
            isActive and AccentDim(i, 0.65) or C.bg_side, 50)
        local tglow = Layer(bgPanel, 12, ty - 2, LEFT_TAB_W - 24, pTabH + 4,
            AccentColor(i, isActive and 0.35 or 0.0), 49, false, true, i)
        local bar = Layer(bgPanel, 14, ty, 4, pTabH, AccentColor(i), 55)
        local underGlow = Layer(bgPanel, 14, ty + pTabH - 2, LEFT_TAB_W - 28, 2,
            AccentColor(i, 0.6), 55)
        if not isActive then
            pcall(function()
                bar:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                underGlow:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
            end)
        end
        local icon = Text(bgPanel, PARENT_ICONS[i], 30, ty + pTabH * 0.5, 14,
            isActive and AccentDeep(i) or C.text_muted, 60, 0.5, 0.5)
        local ttxt = Text(bgPanel, _G.U5LTab(i), 52, ty + pTabH * 0.5, 13,
            isActive and C.text_bright or C.text_dim, 300, 0, 0.5)
        MakeCorners(bgPanel, 14, ty, LEFT_TAB_W - 28, pTabH,
            AccentColor(i, isActive and 1.0 or 0.30), 56, 6, 1)

        parentTabButtons[i] = {
            bg = tbg, txt = ttxt, icon = icon, bar = bar,
            glow = tglow, underGlow = underGlow,
        }
        MakeBtn(bgPanel, 14, ty, LEFT_TAB_W - 28, pTabH, 900, function()
            SwitchParentTab(i)
        end)
    end

    -- 子标签栏
    local subTabY = HEADER_H
    Layer(bgPanel, HX, subTabY, M_W - HX, SUB_TAB_H,
        C.bg_header, 2)
    Divider(bgPanel, HX, subTabY + SUB_TAB_H - 1,
        M_W - HX, C.border, 3)

    local function MakeSubTabs(parentIdx, names)
        local n = #names
        local subTabW = (M_W - HX) / n
        for i = 1, n do
            local tx = HX + (i - 1) * subTabW
            local isActive = (i == 1)
            local tbg = Layer(bgPanel, tx, subTabY, subTabW, SUB_TAB_H,
                isActive and AccentDim(parentIdx, 0.40) or C.bg_header, 50)
            if i > 1 then Divider(bgPanel, tx, subTabY + 8, 1, C.divider, 55) end
            local underline = Layer(bgPanel,
                tx + subTabW * 0.25, subTabY + SUB_TAB_H - 3,
                subTabW * 0.5, 3, AccentColor(parentIdx), 60)
            local ttxt = Text(bgPanel, names[i], tx + subTabW * 0.5,
                subTabY + SUB_TAB_H * 0.5, 12,
                isActive and C.text_bright or C.text_dim, 70, 0.5, 0.5)
            local tbtn = MakeBtn(bgPanel, tx, subTabY, subTabW, SUB_TAB_H, 900,
                function() SwitchSubTab(i) end)
            if not (isActive and parentIdx == 1) then
                pcall(function()
                    tbg:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                    ttxt:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                    underline:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                    if tbtn then
                        tbtn:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                    end
                end)
            end
            subTabButtons[parentIdx][i] = {
                bg = tbg, txt = ttxt, underline = underline, btn = tbtn
            }
        end
    end
    MakeSubTabs(1, TAB_NAMES_WALLHACK)
    MakeSubTabs(2, TAB_NAMES_ESP)
    MakeSubTabs(3, TAB_NAMES_RANGE)
    MakeSubTabs(4, TAB_NAMES_GUN)
    MakeSubTabs(5, TAB_NAMES_BASIC)
    MakeSubTabs(6, TAB_NAMES_AIM)

    -- 内容容器
    local contentX = HX
    local contentY = HEADER_H + SUB_TAB_H
    local contentW = M_W - HX
    local contentH = M_H - contentY - FOOTER_H

    local function MakePanels(pIdx, count)
        for i = 1, count do
            local scrollBox = nil
            local inner = nil
            pcall(function()
                scrollBox = CGame:NewObjectFromPath("/Script/UMG.ScrollBox", bgPanel)
                if scrollBox and slua.isValid(scrollBox) then
                    local slot = bgPanel:AddChildToCanvas(scrollBox)
                    if slot then
                        slot:SetAutoSize(false)
                        slot:SetPosition(FVector2D(contentX, contentY))
                        slot:SetSize(FVector2D(contentW, contentH))
                        slot:SetZOrder(20)
                    end
                    scrollBox:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                    pcall(function()
                        if scrollBox.SetScrollBarVisibility then
                            scrollBox:SetScrollBarVisibility(
                                UEnums.ESlateVisibility.Collapsed)
                        end
                    end)
                    pcall(function()
                        if scrollBox.SetConsumeMouseWheel then
                            scrollBox:SetConsumeMouseWheel(true)
                        end
                    end)
                    local sizeBox = CGame:NewObjectFromPath("/Script/UMG.SizeBox", scrollBox)
                    if sizeBox and slua.isValid(sizeBox) then
                        pcall(function() sizeBox:SetWidthOverride(contentW) end)
                        pcall(function() sizeBox:SetHeightOverride(5000) end)
                        scrollBox:AddChild(sizeBox)
                        inner = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", sizeBox)
                        if inner and slua.isValid(inner) then
                            sizeBox:AddChild(inner)
                        end
                    end
                end
            end)
            subTabScrollBoxes[pIdx][i] = scrollBox or bgPanel
            subTabPanels[pIdx][i] = inner or bgPanel
        end
    end
    MakePanels(1, 4); MakePanels(2, 4); MakePanels(3, 4)
    MakePanels(4, 4); MakePanels(5, 2); MakePanels(6, 7)

    local cw = contentW

    local function buildRowsFromData(panel, tabIdx, rowsData)
        local g = NewGrid(cw)
        for _, r in ipairs(rowsData) do
            if r.type == "section" then
                local x, y, w = g:fullRow()
                MakeSectionLabel(panel, r.label, x, y, w, tabIdx)
            elseif r.type == "toggle" then
                local x, y, w = g:next()
                MakeToggleRow(panel, r.label, x, y, w, r.key,
                    r.cfg, r.save, tabIdx)
            elseif r.type == "slider" then
                local x, y, w = g:next()
                MakeSliderRow(panel, r.label, x, y, w, r.key,
                    r.min, r.max, r.step, r.cfg, r.save, tabIdx)
            end
        end
    end

    local function T2(key, label, cfg, save)
        return { type="toggle", key=key, label=label, cfg=cfg, save=save }
    end
    local function S2(key, label, min, max, step, cfg, save)
        return { type="slider", key=key, label=label, min=min, max=max,
                 step=step, cfg=cfg, save=save }
    end
    local function SEC2(label) return { type="section", label=label } end

    -- 内透
    buildRowsFromData(subTabPanels[1][1], 1, {
        T2("ENEMY_RAINBOW", "敌人彩虹", _G.U5Config, "Wallhack"),
        T2("ENEMY_SINGLE_COLOR", "敌人单色", _G.U5Config, "Wallhack"),
        T2("OUTLINE_SHOW_BOT", "轮廓显示人机", _G.U5Config, "Wallhack"),
        S2("ENEMY_THICKNESS", "厚度", 1, 20, 1, _G.U5Config, "Wallhack"),
        S2("ENEMY_R", "红色 R", 0, 255, 1, _G.U5Config, "Wallhack"),
        S2("ENEMY_G", "绿色 G", 0, 255, 1, _G.U5Config, "Wallhack"),
        S2("ENEMY_B", "蓝色 B", 0, 255, 1, _G.U5Config, "Wallhack"),
        S2("ENEMY_A", "透明度 A", 0, 255, 1, _G.U5Config, "Wallhack"),
    })
    buildRowsFromData(subTabPanels[1][2], 1, {
        T2("GUN_RAINBOW", "武器彩虹", _G.U5Config, "Wallhack"),
        T2("GUN_SINGLE_COLOR", "武器单色", _G.U5Config, "Wallhack"),
        S2("GUN_THICKNESS", "厚度", 1, 20, 1, _G.U5Config, "Wallhack"),
        S2("GUN_R", "红色 R", 0, 255, 1, _G.U5Config, "Wallhack"),
        S2("GUN_G", "绿色 G", 0, 255, 1, _G.U5Config, "Wallhack"),
        S2("GUN_B", "蓝色 B", 0, 255, 1, _G.U5Config, "Wallhack"),
        S2("GUN_A", "透明度 A", 0, 255, 1, _G.U5Config, "Wallhack"),
    })
    buildRowsFromData(subTabPanels[1][3], 1, {
        T2("PLAYER_WALLHACK", "开启人物内透", _G.U5Config, "Wallhack"),
        T2("DJ_SHOW_BOT", "显示人机", _G.U5Config, "Wallhack"),
        S2("DJ_VISIBLE_COLOR", "可见颜色 (1-6)", 1, 6, 1, _G.U5Config, "Wallhack"),
        S2("DJ_HIDDEN_COLOR", "遮挡颜色 (1-6)", 1, 6, 1, _G.U5Config, "Wallhack"),
    })
    buildRowsFromData(subTabPanels[1][4], 1, {
        S2("COLOR_BRIGHTNESS", "颜色亮度", 0.5, 5.0, 0.1,
            _G.U5Config, "Wallhack"),
    })

    -- 绘制
    buildRowsFromData(subTabPanels[2][1], 2, {
        SEC2("── 武器信息 ──"),
        T2("INFO_ESP", "显示武器信息", _G.U5ESPConfig, "ESP"),
        T2("INFO_SHOW_BOT", "显示人机", _G.U5ESPConfig, "ESP"),
        S2("INFO_DISTANCE", "绘制距离(米)", 50, 500, 10, _G.U5ESPConfig, "ESP"),
        S2("INFO_FONT_SIZE", "文字大小", 0.1, 2.0, 0.1, _G.U5ESPConfig, "ESP"),
        S2("INFO_X", "X偏移", -1000, 1000, 10, _G.U5ESPConfig, "ESP"),
        S2("INFO_Y", "Y偏移", -1000, 1000, 10, _G.U5ESPConfig, "ESP"),
        S2("INFO_Z", "Z偏移", -500, 500, 5, _G.U5ESPConfig, "ESP"),
        S2("INFO_R", "颜色R", 0, 255, 1, _G.U5ESPConfig, "ESP"),
        S2("INFO_G", "颜色G", 0, 255, 1, _G.U5ESPConfig, "ESP"),
        S2("INFO_B", "颜色B", 0, 255, 1, _G.U5ESPConfig, "ESP"),
        S2("INFO_A", "透明度", 0, 255, 1, _G.U5ESPConfig, "ESP"),
    })
    buildRowsFromData(subTabPanels[2][2], 2, {
        T2("DIST_ESP", "显示距离", _G.U5ESPConfig, "ESP"),
        T2("DIST_SHOW_BOT", "显示人机", _G.U5ESPConfig, "ESP"),
        S2("DIST_DISTANCE", "绘制距离(米)", 50, 500, 10, _G.U5ESPConfig, "ESP"),
        S2("DIST_FONT_SIZE", "文字大小", 0.1, 2.0, 0.1, _G.U5ESPConfig, "ESP"),
        S2("DIST_X", "X偏移", -1000, 1000, 10, _G.U5ESPConfig, "ESP"),
        S2("DIST_Y", "Y偏移", -1000, 1000, 10, _G.U5ESPConfig, "ESP"),
        S2("DIST_Z", "Z偏移", -500, 500, 5, _G.U5ESPConfig, "ESP"),
        S2("DIST_R", "颜色R", 0, 255, 1, _G.U5ESPConfig, "ESP"),
        S2("DIST_G", "颜色G", 0, 255, 1, _G.U5ESPConfig, "ESP"),
        S2("DIST_B", "颜色B", 0, 255, 1, _G.U5ESPConfig, "ESP"),
        S2("DIST_A", "透明度", 0, 255, 1, _G.U5ESPConfig, "ESP"),
    })
    buildRowsFromData(subTabPanels[2][3], 2, {
        T2("BOX_ESP", "显示死亡盒子", _G.U5ESPConfig, "ESP"),
        T2("BOX_SHOW_BOT", "显示人机盒子", _G.U5ESPConfig, "ESP"),
        S2("BOX_DISTANCE", "绘制距离(米)", 20, 300, 10, _G.U5ESPConfig, "ESP"),
        S2("BOX_FONT_SIZE", "文字大小", 0.5, 3.0, 0.1, _G.U5ESPConfig, "ESP"),
        S2("BOX_COUNT", "显示数量", 1, 50, 1, _G.U5ESPConfig, "ESP"),
        S2("BOX_X", "X偏移", -1000, 1000, 10, _G.U5ESPConfig, "ESP"),
        S2("BOX_Y", "Y偏移", -1000, 1000, 10, _G.U5ESPConfig, "ESP"),
        S2("BOX_Z", "Z偏移", -1000, 1000, 10, _G.U5ESPConfig, "ESP"),
        S2("BOX_R", "颜色R", 0, 255, 1, _G.U5ESPConfig, "ESP"),
        S2("BOX_G", "颜色G", 0, 255, 1, _G.U5ESPConfig, "ESP"),
        S2("BOX_B", "颜色B", 0, 255, 1, _G.U5ESPConfig, "ESP"),
        S2("BOX_A", "透明度", 0, 255, 1, _G.U5ESPConfig, "ESP"),
    })
    buildRowsFromData(subTabPanels[2][4], 2, {
        T2("NATIVE_ESP", "原生绘制总开关", _G.U5ESPConfig, "ESP"),
        T2("NATIVE_SHOW_BOT", "显示人机", _G.U5ESPConfig, "ESP"),
        T2("NATIVE_HP_BAR", "地图标记血条", _G.U5ESPConfig, "ESP"),
        T2("NATIVE_FRAME", "原生敌人方框", _G.U5ESPConfig, "ESP"),
        S2("NATIVE_DISTANCE", "绘制距离(米)", 50, 600, 10,
            _G.U5ESPConfig, "ESP"),
    })

    -- 范围
    buildRowsFromData(subTabPanels[3][1], 3, {
        S2("HEAD", "头部放大 (%)", 0, 200, 1, _G.U5RangeConfig, "Range"),
        S2("NECK", "脖子放大 (%)", 0, 200, 1, _G.U5RangeConfig, "Range"),
        S2("PELVIS", "骨盆放大 (%)", 0, 200, 1, _G.U5RangeConfig, "Range"),
        S2("SPINE", "脊椎放大 (%)", 0, 200, 1, _G.U5RangeConfig, "Range"),
    })
    buildRowsFromData(subTabPanels[3][2], 3, {
        S2("UPPERARM", "上臂放大 (%)", 0, 200, 1, _G.U5RangeConfig, "Range"),
        S2("LOWERARM", "前臂放大 (%)", 0, 200, 1, _G.U5RangeConfig, "Range"),
        S2("HAND", "手部放大 (%)", 0, 200, 1, _G.U5RangeConfig, "Range"),
    })
    buildRowsFromData(subTabPanels[3][3], 3, {
        S2("THIGH", "大腿放大 (%)", 0, 200, 1, _G.U5RangeConfig, "Range"),
        S2("CALF", "小腿放大 (%)", 0, 200, 1, _G.U5RangeConfig, "Range"),
        S2("FOOT", "脚部放大 (%)", 0, 200, 1, _G.U5RangeConfig, "Range"),
    })
    buildRowsFromData(subTabPanels[3][4], 3, {
        SEC2("── 范围总开关 ──"),
        T2("ENABLED", "启用 Hitbox 放大", _G.U5RangeConfig, "Range"),
    })

    -- 枪械
    buildRowsFromData(subTabPanels[4][1], 4, {
        T2("NO_RECOIL_ADS", "无后座（无跳弹）", _G.GunFuncConfig, "GunFunc"),
        T2("ANTI_SHAKE", "防抖", _G.GunFuncConfig, "GunFunc"),
        S2("EXTRA_HIT_SCALE", "X特效 (命中反馈)", 0, 10, 0.1,
            _G.GunFuncConfig, "GunFunc"),
    })
    buildRowsFromData(subTabPanels[4][2], 4, {
        T2("SUPER_FIRE_RATE", "超快射速", _G.GunFuncConfig, "GunFunc"),
        S2("FIRE_RATE_VALUE", "射速值 (秒/发)", 0.001, 0.2, 0.001,
            _G.GunFuncConfig, "GunFunc"),
    })
    buildRowsFromData(subTabPanels[4][3], 4, {
        T2("ALL_GUN_FOCUS", "全枪聚点", _G.GunFuncConfig, "GunFunc"),
        S2("FOCUS_VALUE", "聚点值 (0-1)", 0, 1, 0.01,
            _G.GunFuncConfig, "GunFunc"),
    })
    buildRowsFromData(subTabPanels[4][4], 4, {
        T2("QUICK_SCOPE", "秒开镜", _G.GunFuncConfig, "GunFunc"),
        S2("SCOPE_VALUE", "开镜速度值", 0, 100, 1, _G.GunFuncConfig, "GunFunc"),
        T2("QUICK_SWITCH", "快速切枪", _G.GunFuncConfig, "GunFunc"),
        S2("SWITCH_VALUE", "切枪速度值", 0, 100, 1, _G.GunFuncConfig, "GunFunc"),
    })

    -- 基本
    buildRowsFromData(subTabPanels[5][1], 5, {
        T2("WIDE_ANGLE", "广角总开关", _G.BasicFuncConfig, "BasicFunc"),
        S2("TP_FOV", "第三人称视野", 60, 120, 1, _G.BasicFuncConfig, "BasicFunc"),
        S2("SCOPE_FOV", "开镜视野（瞄准臂长）", 0, 100, 1,
            _G.BasicFuncConfig, "BasicFunc"),
        T2("MEMORY_FOV", "内存广角", _G.BasicFuncConfig, "BasicFunc"),
        S2("MEMORY_FOV_VALUE", "内存广角值", 60, 160, 1,
            _G.BasicFuncConfig, "BasicFunc"),
    })
    buildRowsFromData(subTabPanels[5][2], 5, {
        S2("LOCK_FPS", "锁帧（0=关闭）", 0, 240, 1,
            _G.BasicFuncConfig, "BasicFunc"),
        T2("PERFORMANCE_OPT", "性能优化（降画质提帧）",
            _G.BasicFuncConfig, "BasicFunc"),
    })

    -- 自瞄
    buildRowsFromData(subTabPanels[6][1], 6, {
        T2("ENABLED", "自瞄总开关", _G.AimBotConfig, "AimBot"),
        T2("HIP_AIM", "腰射自瞄", _G.AimBotConfig, "AimBot"),
        T2("FIRE_AIM", "开火自瞄", _G.AimBotConfig, "AimBot"),
        T2("SCOPE_FIRE_AIM", "开镜开火自瞄", _G.AimBotConfig, "AimBot"),
        T2("SCOPE_AIM", "开镜自瞄（不开火）", _G.AimBotConfig, "AimBot"),
        T2("AIM_BOT", "瞄准人机", _G.AimBotConfig, "AimBot"),
        T2("WALL_CHECK", "穿墙检测（不瞄掩体）", _G.AimBotConfig, "AimBot"),
        T2("AIM_KNOCK", "瞄准倒地敌人", _G.AimBotConfig, "AimBot"),
        S2("AIM_PRIORITY", "优先级 (0距离+屏幕 1屏幕 2距离)", 0, 2, 1,
            _G.AimBotConfig, "AimBot"),
    })
    buildRowsFromData(subTabPanels[6][2], 6, {
        S2("HIP_BONE", "腰射部位 (0头 1胸 2骨盆)", 0, 2, 1,
            _G.AimBotConfig, "AimBot"),
        S2("FIRE_BONE", "开火部位 (0头 1胸 2骨盆)", 0, 2, 1,
            _G.AimBotConfig, "AimBot"),
        S2("SCOPE_FIRE_BONE", "开镜开火部位", 0, 2, 1,
            _G.AimBotConfig, "AimBot"),
        S2("SCOPE_BONE", "开镜部位", 0, 2, 1, _G.AimBotConfig, "AimBot"),
    })
    buildRowsFromData(subTabPanels[6][3], 6, {
        S2("HIP_DIST", "腰射自瞄距离 (米)", 1, 200, 1, _G.AimBotConfig, "AimBot"),
        S2("HIP_SPEED", "腰射速度", 1, 200, 1, _G.AimBotConfig, "AimBot"),
        S2("HIP_RECOIL", "腰射压枪值", 0, 50, 1, _G.AimBotConfig, "AimBot"),
        S2("FIRE_DIST", "开火自瞄距离 (米)", 1, 400, 1, _G.AimBotConfig, "AimBot"),
        S2("FIRE_SPEED", "开火速度", 1, 200, 1, _G.AimBotConfig, "AimBot"),
        S2("FIRE_RECOIL", "开火压枪值", 0, 50, 1, _G.AimBotConfig, "AimBot"),
        S2("SCOPE_FIRE_DIST", "开镜开火自瞄距离 (米)", 1, 500, 1,
            _G.AimBotConfig, "AimBot"),
        S2("SCOPE_FIRE_NO_AIM_DIST", "开镜开火不自瞄距离 (米)", 0, 100, 1,
            _G.AimBotConfig, "AimBot"),
        S2("SCOPE_FIRE_SPEED", "开镜开火速度", 1, 200, 1,
            _G.AimBotConfig, "AimBot"),
        S2("SCOPE_FIRE_RECOIL", "开镜开火压枪值", 0, 50, 1,
            _G.AimBotConfig, "AimBot"),
        S2("SCOPE_DIST", "开镜自瞄距离 (米)", 1, 500, 1,
            _G.AimBotConfig, "AimBot"),
        S2("SCOPE_NO_AIM_DIST", "开镜不自瞄距离 (米)", 0, 100, 1,
            _G.AimBotConfig, "AimBot"),
        S2("SCOPE_SPEED", "开镜速度", 1, 200, 1, _G.AimBotConfig, "AimBot"),
    })
    buildRowsFromData(subTabPanels[6][4], 6, {
        T2("AIM_PREDICTION", "移动预判", _G.AimBotConfig, "AimBot"),
        S2("PREDICTION_STRENGTH", "预判强度 (0-100)", 0, 100, 1,
            _G.AimBotConfig, "AimBot"),
        S2("PREDICTION_MAX_TIME", "预判最大时间 (0.1-0.8秒)", 0.1, 0.8, 0.1,
            _G.AimBotConfig, "AimBot"),
        S2("PREDICTION_SMOOTH", "速度平滑 (0-100)", 0, 100, 1,
            _G.AimBotConfig, "AimBot"),
    })
    buildRowsFromData(subTabPanels[6][5], 6, {
        T2("AIM_SNAP", "近距离吸附", _G.AimBotConfig, "AimBot"),
        S2("AIM_SNAP_ANGLE", "吸附阈值 (0.0-2.0度)", 0, 2, 0.1,
            _G.AimBotConfig, "AimBot"),
        S2("AIM_DEADZONE", "死区 (0.00-0.20度)", 0, 0.2, 0.01,
            _G.AimBotConfig, "AimBot"),
        S2("PITCH_SPEED_FACTOR", "垂直速度系数 (0.3-2.0)", 0.3, 2.0, 0.1,
            _G.AimBotConfig, "AimBot"),
        T2("TARGET_LOCK", "目标锁定", _G.AimBotConfig, "AimBot"),
        S2("LOCK_FOV_FACTOR", "锁定FOV放宽 (1.0-3.0倍)", 1.0, 3.0, 0.1,
            _G.AimBotConfig, "AimBot"),
        T2("AIM_POINT_ADAPT", "距离自适应部位", _G.AimBotConfig, "AimBot"),
        S2("AIM_POINT_DIST", "自适应切换距离 (米)", 10, 200, 1,
            _G.AimBotConfig, "AimBot"),
    })
    buildRowsFromData(subTabPanels[6][6], 6, {
        T2("BULLET_DROP_COMP", "弹道补偿", _G.AimBotConfig, "AimBot"),
        S2("BULLET_DROP_SCALE", "弹道补偿强度 (%)", 0, 200, 1,
            _G.AimBotConfig, "AimBot"),
        S2("BULLET_DROP_MIN_DIST", "弹道补偿最小距离 (米)", 10, 200, 1,
            _G.AimBotConfig, "AimBot"),
        S2("BULLET_SPEED", "默认子弹速度 (米/秒)", 300, 1000, 1,
            _G.AimBotConfig, "AimBot"),
        T2("RECOIL_RAMP", "压枪递增", _G.AimBotConfig, "AimBot"),
    })
    buildRowsFromData(subTabPanels[6][7], 6, {
        SEC2("── 显示设置 ──"),
        T2("FOV_CIRCLE", "显示FOV圈", _G.AimBotConfig, "AimBot"),
        S2("FOV_CIRCLE_COLOR", "FOV圈颜色 (1-7)", 1, 7, 1,
            _G.AimBotConfig, "AimBot"),
        S2("FOV_CIRCLE_THICKNESS", "FOV圈粗细 (1-5)", 1, 5, 1,
            _G.AimBotConfig, "AimBot"),
        S2("FOV_CIRCLE_MODE", "FOV圈模式 (0固定 1跟随)", 0, 1, 1,
            _G.AimBotConfig, "AimBot"),
        T2("FOV_CIRCLE_VIS_MODE", "FOV圈掩体变色", _G.AimBotConfig, "AimBot"),
        S2("FOV_CIRCLE_VIS_COLOR", "可见颜色 (1-7)", 1, 7, 1,
            _G.AimBotConfig, "AimBot"),
        S2("FOV_CIRCLE_COVER_COLOR", "遮挡颜色 (1-7)", 1, 7, 1,
            _G.AimBotConfig, "AimBot"),
        SEC2("── 自瞄范围（FOV圈同步） ──"),
        S2("HIP_FOV", "腰射范围 (度)", 1, 90, 1, _G.AimBotConfig, "AimBot"),
        S2("FIRE_FOV", "开火范围 (度)", 1, 90, 1, _G.AimBotConfig, "AimBot"),
        S2("SCOPE_FIRE_FOV", "开镜开火范围 (度)", 1, 90, 1,
            _G.AimBotConfig, "AimBot"),
        S2("SCOPE_FOV", "开镜范围 (度)", 1, 90, 1, _G.AimBotConfig, "AimBot"),
    })

    -- 底部（v5.4 轻主题：仅保留文字装饰）
    Text(bgPanel, "内透 / 绘制 / 范围 / 枪械 / 基本 / 自瞄",
        HX + 14, M_H - FOOTER_H * 0.5, 9, C.text_muted, 100, 0, 0.5)
    Text(bgPanel, "U5  •  v5.4", M_W - 14, M_H - FOOTER_H * 0.5, 9,
        C.text_dim, 100, 1, 0.5)

    if _G.U5UIState.showPerf == 1 then
        _G._U5_PerfText = Text(bgPanel, "FPS --", M_W - 160,
            M_H - FOOTER_H*0.5, 9, C.text_dim, 100, 0, 0.5, false, true)
    end

menuBuilt = true
    isMenuOpen = true
    SwitchParentTab(1)
    SwitchSubTab(1)

    -- ★ 首次创建 → 走打开动画（而不是直接显示）
    _G.U5AnimateMenuOpen()

    -- 动画定时器
    pcall(function()
        local pc = slua_GameFrontendHUD and
            slua_GameFrontendHUD:GetPlayerController()
        if pc then
            pc:AddGameTimer(0.05, true, function()
                pcall(function()
                    _G.U5UpdateTweens(0.05)
                    _G.U5UpdateDrag()
                    _G.U5UpdatePerf()

                    UpdateRGB()
                    for _, w in ipairs(rgbWidgets) do
                        if w and IsValidUI(w) then
                            pcall(function() w:SetBrushColor(RGBColor(0.30)) end)
                        end
                    end

                    local tm = os.clock() * 2.0
                    for _, item in ipairs(pulseWidgets) do
                        if item.widget and IsValidUI(item.widget) then
                            local k = 0.65 + 0.35 * math.sin(tm + item.phase)
                            local base = item.base
                            pcall(function()
                                item.widget:SetBrushColor(FLinearColor(
                                    base.R * k, base.G * k, base.B * k, base.A))
                            end)
                        end
                    end

                    if _G._U5_CrumbText and IsValidUI(_G._U5_CrumbText) then
                        local name = _G.U5LTab(currentParentTab) or ""
                        local col = AccentDeep(currentParentTab)
                        pcall(function()
                            _G._U5_CrumbText:SetText("● " .. name)
                            if FSlateColor then
                                _G._U5_CrumbText:SetColorAndOpacity(FSlateColor(col))
                            else
                                _G._U5_CrumbText:SetColorAndOpacity(col)
                            end
                        end)
                    end
                end)
            end)
        end
    end)
end

-- ============================================================
-- U5 圆形启动按钮 · 像素画数据（由 logo.png 转换生成）
-- 网格 74x74（cell=1.0px @ 62px 按钮），格式 {row,col,w,h,idx}
-- idx: 1..7 = 灰度（1最暗 → 7最亮）
-- 101=内圈脉冲环 103=分隔暗环 201=RGB外发光 202=主亮环
-- ============================================================
_G.U5LogoGrid = 74
_G.U5LogoCell = 1.0
_G.U5LogoOffset = 6
_G.U5LogoPal = {
    [1] = {0.071, 0.071, 0.071},
    [2] = {0.214, 0.214, 0.214},
    [3] = {0.357, 0.357, 0.357},
    [4] = {0.500, 0.500, 0.500},
    [5] = {0.643, 0.643, 0.643},
    [6] = {0.786, 0.786, 0.786},
    [7] = {0.931, 0.931, 0.931},
}
_G.U5LogoData = {
{1,29,16,1,201},
{2,25,24,1,201},
{3,23,28,1,201},
{4,20,34,1,201},
{5,19,12,1,201},
{5,43,12,1,201},
{6,17,10,1,201},
{6,47,10,1,201},
{7,16,9,1,201},
{7,49,9,1,201},
{8,14,8,1,201},
{8,52,8,1,201},
{9,13,8,1,201},
{9,53,8,1,201},
{10,12,7,1,201},
{10,55,7,1,201},
{11,11,7,1,201},
{11,56,7,1,201},
{12,10,6,1,201},
{12,58,6,1,201},
{13,9,6,1,201},
{13,59,6,1,201},
{14,8,6,1,201},
{14,60,6,1,201},
{15,8,5,1,201},
{15,61,5,1,201},
{16,7,5,1,201},
{16,62,5,1,201},
{17,6,6,1,201},
{17,62,6,1,201},
{18,6,5,1,201},
{18,63,5,1,201},
{19,5,5,1,201},
{19,64,5,1,201},
{20,4,6,1,201},
{20,64,6,1,201},
{21,4,5,1,201},
{21,65,5,1,201},
{22,4,4,1,201},
{22,66,4,1,201},
{23,3,5,2,201},
{23,66,5,2,201},
{25,2,5,2,201},
{25,67,5,2,201},
{27,2,4,2,201},
{27,68,4,2,201},
{29,1,5,2,201},
{29,68,5,2,201},
{31,1,4,12,201},
{31,69,4,12,201},
{43,1,5,2,201},
{43,68,5,2,201},
{45,2,4,2,201},
{45,68,4,2,201},
{47,2,5,2,201},
{47,67,5,2,201},
{49,3,5,2,201},
{49,66,5,2,201},
{51,4,4,1,201},
{51,66,4,1,201},
{52,4,5,1,201},
{52,65,5,1,201},
{53,4,6,1,201},
{53,64,6,1,201},
{54,5,5,1,201},
{54,64,5,1,201},
{55,6,5,1,201},
{55,63,5,1,201},
{56,6,6,1,201},
{56,62,6,1,201},
{57,7,5,1,201},
{57,62,5,1,201},
{58,8,5,1,201},
{58,61,5,1,201},
{59,8,6,1,201},
{59,60,6,1,201},
{60,9,6,1,201},
{60,59,6,1,201},
{61,10,6,1,201},
{61,58,6,1,201},
{62,11,7,1,201},
{62,56,7,1,201},
{63,12,7,1,201},
{63,55,7,1,201},
{64,13,8,1,201},
{64,53,8,1,201},
{65,14,8,1,201},
{65,52,8,1,201},
{66,16,9,1,201},
{66,49,9,1,201},
{67,17,10,1,201},
{67,47,10,1,201},
{68,19,12,1,201},
{68,43,12,1,201},
{69,20,34,1,201},
{70,23,28,1,201},
{71,25,24,1,201},
{72,29,16,1,201},
{9,35,4,1,7},
{10,29,16,1,7},
{11,26,22,1,7},
{12,24,24,1,7},
{13,23,1,1,7},
{13,25,23,2,7},
{14,21,3,1,7},
{14,51,2,1,7},
{15,20,3,1,7},
{15,25,16,2,7},
{15,42,7,1,7},
{15,51,3,1,7},
{16,19,3,1,7},
{16,43,3,1,7},
{16,47,2,2,7},
{16,52,3,1,7},
{17,17,4,1,7},
{17,22,1,2,7},
{17,24,16,2,7},
{17,52,5,2,7},
{18,17,2,1,7},
{18,20,1,1,7},
{18,47,3,1,7},
{19,16,7,1,7},
{19,24,1,1,7},
{19,26,13,1,7},
{19,47,11,1,7},
{20,15,8,1,7},
{20,28,11,1,7},
{20,48,2,1,7},
{20,51,8,1,7},
{21,15,7,2,7},
{21,29,9,1,7},
{21,49,1,1,7},
{21,51,9,1,7},
{22,30,6,1,7},
{22,37,1,1,7},
{22,51,6,1,7},
{22,58,2,1,7},
{23,13,9,1,7},
{23,31,4,1,7},
{23,46,1,2,7},
{23,51,1,1,7},
{23,53,1,1,7},
{23,58,3,1,7},
{24,12,10,2,7},
{24,32,3,1,7},
{24,58,4,2,7},
{25,33,1,1,7},
{26,11,1,3,7},
{26,15,6,2,7},
{26,42,2,1,7},
{26,58,5,3,7},
{27,38,11,1,7},
{28,13,7,1,7},
{28,37,12,1,7},
{29,10,2,1,7},
{29,13,5,1,7},
{29,19,1,2,7},
{29,30,2,1,7},
{29,37,13,1,7},
{29,58,6,5,7},
{30,10,8,1,7},
{30,30,20,1,7},
{31,10,3,2,7},
{31,16,3,1,7},
{31,28,22,1,7},
{31,54,1,1,7},
{32,16,5,1,7},
{32,27,23,1,7},
{32,53,3,3,7},
{33,10,9,2,7},
{33,20,1,2,7},
{33,25,25,2,7},
{34,57,7,1,7},
{35,9,10,1,7},
{35,25,24,2,7},
{35,53,2,1,7},
{35,57,8,4,7},
{36,9,9,3,7},
{37,26,23,1,7},
{38,27,22,1,7},
{39,10,8,1,7},
{39,20,1,1,7},
{39,27,21,1,7},
{39,56,8,3,7},
{40,10,5,1,7},
{40,16,2,1,7},
{40,20,2,2,7},
{40,28,19,1,7},
{40,54,1,1,7},
{41,10,8,1,7},
{41,26,1,1,7},
{41,29,17,1,7},
{42,10,13,2,7},
{42,25,3,1,7},
{42,30,16,1,7},
{42,55,9,2,7},
{43,24,5,1,7},
{43,32,13,1,7},
{44,10,19,1,7},
{44,34,10,1,7},
{44,53,11,1,7},
{45,11,17,2,7},
{45,35,8,1,7},
{45,53,10,1,7},
{46,38,4,1,7},
{46,52,11,2,7},
{47,11,18,1,7},
{48,12,18,2,7},
{48,45,2,1,7},
{48,52,10,2,7},
{49,44,3,1,7},
{50,13,17,1,7},
{50,35,1,1,7},
{50,42,5,1,7},
{50,52,9,1,7},
{51,14,15,2,7},
{51,35,2,1,7},
{51,40,6,1,7},
{51,52,8,1,7},
{52,35,10,1,7},
{52,48,2,1,7},
{52,53,7,1,7},
{53,15,13,1,7},
{53,32,2,1,7},
{53,36,8,1,7},
{53,47,3,1,7},
{53,54,5,1,7},
{54,16,12,1,7},
{54,32,3,1,7},
{54,37,6,1,7},
{54,46,4,1,7},
{54,55,3,1,7},
{55,17,10,1,7},
{55,31,5,1,7},
{55,39,3,1,7},
{55,45,5,1,7},
{55,55,2,1,7},
{56,17,9,1,7},
{56,31,6,1,7},
{56,43,7,1,7},
{56,56,1,1,7},
{57,19,4,1,7},
{57,32,6,2,7},
{57,42,8,2,7},
{58,20,2,1,7},
{59,32,5,4,7},
{59,43,7,3,7},
{62,44,4,1,7},
{63,32,4,1,7},
{63,44,1,1,7},
{64,35,1,1,7},
{12,48,2,1,6},
{13,24,1,2,6},
{13,48,3,2,6},
{15,23,2,1,6},
{15,41,1,1,6},
{15,49,2,1,6},
{16,22,3,1,6},
{16,41,2,1,6},
{16,46,1,1,6},
{16,49,3,2,6},
{17,21,1,2,6},
{17,23,1,3,6},
{17,40,1,2,6},
{17,42,5,1,6},
{18,19,1,1,6},
{18,50,2,1,6},
{19,25,1,1,6},
{19,39,1,1,6},
{20,23,5,1,6},
{20,39,2,1,6},
{20,47,1,1,6},
{20,50,1,2,6},
{21,14,1,2,6},
{21,22,1,2,6},
{21,24,5,1,6},
{21,38,2,2,6},
{22,25,3,1,6},
{22,29,1,1,6},
{22,36,1,1,6},
{22,49,2,2,6},
{22,57,1,2,6},
{23,30,1,1,6},
{23,35,5,1,6},
{23,52,1,1,6},
{23,54,2,1,6},
{24,30,2,1,6},
{24,37,3,1,6},
{24,45,1,1,6},
{24,47,9,1,6},
{25,29,2,1,6},
{25,32,1,1,6},
{25,34,6,1,6},
{25,44,7,2,6},
{25,53,3,4,6},
{26,12,3,2,6},
{26,21,1,2,6},
{26,32,10,1,6},
{27,30,8,1,6},
{27,49,1,1,6},
{28,12,1,2,6},
{28,20,2,3,6},
{28,30,5,1,6},
{28,57,1,1,6},
{29,18,1,2,6},
{29,29,1,2,6},
{29,32,5,1,6},
{29,53,5,2,6},
{31,13,3,2,6},
{31,19,2,1,6},
{31,23,3,1,6},
{31,53,1,1,6},
{31,55,3,1,6},
{32,23,4,1,6},
{32,56,2,2,6},
{33,19,1,2,6},
{33,23,2,2,6},
{34,56,1,1,6},
{35,19,2,1,6},
{35,49,1,1,6},
{35,52,1,1,6},
{35,55,2,1,6},
{36,18,3,3,6},
{36,53,4,3,6},
{37,25,1,1,6},
{38,25,2,1,6},
{39,18,2,3,6},
{39,21,1,1,6},
{39,24,3,1,6},
{39,49,7,1,6},
{40,15,1,1,6},
{40,24,2,2,6},
{40,49,5,1,6},
{40,55,1,1,6},
{41,22,1,1,6},
{41,28,1,1,6},
{41,46,1,1,6},
{41,49,7,1,6},
{42,23,2,1,6},
{42,28,2,1,6},
{42,49,6,1,6},
{43,23,1,1,6},
{43,29,3,2,6},
{43,48,1,3,6},
{43,50,5,1,6},
{44,33,1,1,6},
{44,50,3,2,6},
{45,28,2,1,6},
{45,34,1,1,6},
{46,28,3,1,6},
{46,35,3,1,6},
{46,46,3,1,6},
{46,50,2,2,6},
{47,29,2,1,6},
{47,35,1,2,6},
{47,37,1,1,6},
{47,45,3,1,6},
{48,30,2,1,6},
{48,44,1,1,6},
{48,49,3,2,6},
{49,30,1,2,6},
{49,34,2,1,6},
{49,43,1,1,6},
{50,34,1,2,6},
{50,36,1,1,6},
{50,39,3,1,6},
{50,47,5,1,6},
{51,29,1,1,6},
{51,37,1,1,6},
{51,39,1,1,6},
{51,46,4,1,6},
{52,33,2,1,6},
{52,45,1,1,6},
{52,47,1,1,6},
{53,31,1,2,6},
{53,34,2,1,6},
{53,44,1,1,6},
{54,35,2,1,6},
{54,43,3,1,6},
{55,36,3,1,6},
{55,42,3,1,6},
{56,37,2,1,6},
{57,23,1,1,6},
{57,31,1,4,6},
{59,37,1,2,6},
{63,36,1,1,6},
{17,41,1,1,5},
{18,41,6,1,5},
{19,40,7,1,5},
{20,41,6,1,5},
{21,40,4,1,5},
{21,47,2,1,5},
{22,24,1,1,5},
{22,28,1,1,5},
{22,40,1,1,5},
{22,48,1,1,5},
{23,22,1,2,5},
{23,24,6,1,5},
{23,47,2,1,5},
{23,56,1,1,5},
{24,24,2,1,5},
{24,29,1,1,5},
{24,35,2,1,5},
{24,56,2,4,5},
{25,22,5,1,5},
{25,31,1,1,5},
{25,51,2,1,5},
{26,22,4,1,5},
{26,30,2,1,5},
{27,22,2,1,5},
{27,50,1,1,5},
{28,22,1,2,5},
{28,35,2,1,5},
{28,49,4,1,5},
{28,56,1,1,5},
{29,50,3,3,5},
{30,22,4,1,5},
{30,28,1,1,5},
{31,21,2,1,5},
{31,26,2,1,5},
{32,22,1,2,5},
{32,50,1,1,5},
{32,52,1,1,5},
{33,50,3,2,5},
{34,21,1,2,5},
{35,23,2,1,5},
{35,50,2,1,5},
{36,52,1,2,5},
{38,21,1,1,5},
{38,24,1,1,5},
{38,49,1,1,5},
{39,22,2,2,5},
{39,48,1,1,5},
{40,26,2,1,5},
{40,47,2,1,5},
{41,23,1,1,5},
{41,27,1,1,5},
{43,49,1,4,5},
{44,32,1,1,5},
{45,30,2,1,5},
{45,43,1,1,5},
{45,46,2,1,5},
{46,31,1,1,5},
{46,34,1,1,5},
{46,42,1,1,5},
{46,45,1,1,5},
{47,31,4,1,5},
{47,36,1,1,5},
{47,38,3,1,5},
{47,48,2,1,5},
{48,32,3,1,5},
{48,36,5,1,5},
{48,47,2,2,5},
{49,31,1,1,5},
{49,36,7,1,5},
{50,37,2,1,5},
{51,30,1,1,5},
{51,38,1,1,5},
{52,31,2,1,5},
{52,46,1,1,5},
{53,45,2,1,5},
{54,54,1,1,5},
{56,39,1,1,5},
{56,41,2,1,5},
{21,23,1,1,4},
{21,44,3,1,4},
{22,46,2,1,4},
{24,23,1,1,4},
{24,26,1,1,4},
{24,40,1,1,4},
{25,27,2,1,4},
{25,40,2,1,4},
{26,26,4,1,4},
{26,51,2,2,4},
{27,24,1,1,4},
{27,28,2,1,4},
{28,23,1,2,4},
{28,29,1,1,4},
{32,21,1,2,4},
{32,51,1,1,4},
{34,22,1,2,4},
{36,21,4,1,4},
{36,49,3,2,4},
{37,21,1,1,4},
{37,24,1,1,4},
{38,22,2,1,4},
{38,50,3,1,4},
{41,47,2,1,4},
{42,46,3,1,4},
{43,45,3,1,4},
{44,44,1,1,4},
{44,46,2,1,4},
{45,32,2,2,4},
{45,44,2,1,4},
{46,43,2,1,4},
{47,41,4,1,4},
{48,41,3,1,4},
{49,32,2,1,4},
{50,31,3,2,4},
{55,27,1,1,4},
{56,26,1,1,4},
{56,40,1,1,4},
{57,24,1,1,4},
{57,38,1,1,4},
{58,22,1,1,4},
{59,50,1,2,4},
{61,31,1,1,4},
{61,37,1,1,4},
{64,36,1,1,4},
{22,23,1,2,3},
{22,41,1,1,3},
{22,45,1,2,3},
{23,40,1,1,3},
{24,27,2,1,3},
{24,44,1,1,3},
{25,43,1,1,3},
{27,25,3,1,3},
{28,28,1,2,3},
{30,26,2,1,3},
{37,22,2,1,3},
{44,45,1,1,3},
{51,50,1,1,3},
{53,28,1,1,3},
{57,40,2,1,3},
{57,50,1,2,3},
{58,41,1,1,3},
{59,42,1,2,3},
{62,31,1,1,3},
{62,43,1,1,3},
{22,42,3,1,2},
{23,44,1,1,2},
{25,42,1,1,2},
{28,24,3,1,2},
{29,24,2,1,2},
{51,51,1,1,2},
{52,29,2,1,2},
{52,50,1,5,2},
{52,52,1,1,2},
{53,53,1,1,2},
{56,55,1,1,2},
{57,25,1,1,2},
{57,39,1,1,2},
{58,38,3,1,2},
{59,41,1,2,2},
{62,37,1,1,2},
{63,31,1,1,2},
{63,43,1,1,2},
{23,41,3,2,1},
{28,27,1,1,1},
{29,26,2,1,1},
{52,51,1,1,1},
{53,29,2,1,1},
{53,51,2,1,1},
{54,28,3,2,1},
{54,51,3,1,1},
{55,51,4,3,1},
{56,27,4,1,1},
{57,26,5,1,1},
{58,23,8,1,1},
{58,51,3,1,1},
{59,21,10,1,1},
{59,38,3,2,1},
{59,51,2,1,1},
{60,23,8,1,1},
{61,24,7,1,1},
{61,38,5,2,1},
{62,26,5,1,1},
{63,29,2,1,1},
{63,37,6,1,1},
{64,37,2,1,1},
{7,35,4,1,103},
{8,29,6,1,103},
{8,39,6,1,103},
{9,26,3,1,103},
{9,45,3,1,103},
{10,24,2,1,103},
{10,48,2,1,103},
{11,22,2,1,103},
{11,50,2,1,103},
{12,20,2,1,103},
{12,52,2,1,103},
{13,19,2,1,103},
{13,53,2,1,103},
{14,18,1,1,103},
{14,55,1,1,103},
{15,17,1,1,103},
{15,56,1,1,103},
{16,16,1,1,103},
{16,57,1,1,103},
{17,15,1,1,103},
{17,58,1,1,103},
{18,14,1,1,103},
{18,59,1,1,103},
{19,13,1,1,103},
{19,60,1,1,103},
{20,12,2,1,103},
{20,60,2,1,103},
{21,12,1,1,103},
{21,61,1,1,103},
{22,11,1,2,103},
{22,62,1,2,103},
{24,10,1,2,103},
{24,63,1,2,103},
{26,9,1,3,103},
{26,64,1,3,103},
{29,8,1,6,103},
{29,65,1,6,103},
{35,7,1,4,103},
{35,66,1,4,103},
{39,8,1,6,103},
{39,65,1,6,103},
{45,9,1,3,103},
{45,64,1,3,103},
{48,10,1,2,103},
{48,63,1,2,103},
{50,11,1,2,103},
{50,62,1,2,103},
{52,12,1,1,103},
{52,61,1,1,103},
{53,12,2,1,103},
{53,60,2,1,103},
{54,13,1,1,103},
{54,60,1,1,103},
{55,14,1,1,103},
{55,59,1,1,103},
{56,15,1,1,103},
{56,58,1,1,103},
{57,16,1,1,103},
{57,57,1,1,103},
{58,17,1,1,103},
{58,56,1,1,103},
{59,18,1,1,103},
{59,55,1,1,103},
{60,19,2,1,103},
{60,53,2,1,103},
{61,20,2,1,103},
{61,52,2,1,103},
{62,22,2,1,103},
{62,50,2,1,103},
{63,24,2,1,103},
{63,48,2,1,103},
{64,26,3,1,103},
{64,45,3,1,103},
{65,29,6,1,103},
{65,39,6,1,103},
{66,35,4,1,103},
{8,35,4,1,101},
{9,29,6,1,101},
{9,39,6,1,101},
{10,26,3,1,101},
{10,45,3,1,101},
{11,24,2,1,101},
{11,48,2,1,101},
{12,22,2,1,101},
{12,50,2,1,101},
{13,21,2,1,101},
{13,51,2,1,101},
{14,19,2,1,101},
{14,53,2,1,101},
{15,18,2,1,101},
{15,54,2,1,101},
{16,17,2,1,101},
{16,55,2,1,101},
{17,16,1,1,101},
{17,57,1,1,101},
{18,15,2,1,101},
{18,57,2,1,101},
{19,14,2,1,101},
{19,58,2,1,101},
{20,14,1,1,101},
{20,59,1,1,101},
{21,13,1,1,101},
{21,60,1,1,101},
{22,12,2,1,101},
{22,60,2,1,101},
{23,12,1,1,101},
{23,61,1,1,101},
{24,11,1,2,101},
{24,62,1,2,101},
{26,10,1,3,101},
{26,63,1,3,101},
{29,9,1,6,101},
{29,64,1,6,101},
{35,8,1,4,101},
{35,65,1,4,101},
{39,9,1,6,101},
{39,64,1,6,101},
{45,10,1,3,101},
{45,63,1,3,101},
{48,11,1,2,101},
{48,62,1,2,101},
{50,12,1,1,101},
{50,61,1,1,101},
{51,12,2,1,101},
{51,60,2,1,101},
{52,13,1,1,101},
{52,60,1,1,101},
{53,14,1,1,101},
{53,59,1,1,101},
{54,14,2,1,101},
{54,58,2,1,101},
{55,15,2,1,101},
{55,57,2,1,101},
{56,16,1,1,101},
{56,57,1,1,101},
{57,17,2,1,101},
{57,55,2,1,101},
{58,18,2,1,101},
{58,54,2,1,101},
{59,19,2,1,101},
{59,53,2,1,101},
{60,21,2,1,101},
{60,51,2,1,101},
{61,22,2,1,101},
{61,50,2,1,101},
{62,24,2,1,101},
{62,48,2,1,101},
{63,26,3,1,101},
{63,45,3,1,101},
{64,29,6,1,101},
{64,39,6,1,101},
{65,35,4,1,101},
{5,31,12,1,202},
{6,27,20,1,202},
{7,25,10,1,202},
{7,39,10,1,202},
{8,22,7,1,202},
{8,45,7,1,202},
{9,21,5,1,202},
{9,48,5,1,202},
{10,19,5,1,202},
{10,50,5,1,202},
{11,18,4,1,202},
{11,52,4,1,202},
{12,16,4,1,202},
{12,54,4,1,202},
{13,15,4,1,202},
{13,55,4,1,202},
{14,14,4,1,202},
{14,56,4,1,202},
{15,13,4,1,202},
{15,57,4,1,202},
{16,12,4,1,202},
{16,58,4,1,202},
{17,12,3,1,202},
{17,59,3,1,202},
{18,11,3,1,202},
{18,60,3,1,202},
{19,10,3,1,202},
{19,61,3,1,202},
{20,10,2,1,202},
{20,62,2,1,202},
{21,9,3,1,202},
{21,62,3,1,202},
{22,8,3,2,202},
{22,63,3,2,202},
{24,8,2,1,202},
{24,64,2,1,202},
{25,7,3,1,202},
{25,64,3,1,202},
{26,7,2,1,202},
{26,65,2,1,202},
{27,6,3,2,202},
{27,65,3,2,202},
{29,6,2,2,202},
{29,66,2,2,202},
{31,5,3,4,202},
{31,66,3,4,202},
{35,5,2,4,202},
{35,67,2,4,202},
{39,5,3,4,202},
{39,66,3,4,202},
{43,6,2,2,202},
{43,66,2,2,202},
{45,6,3,2,202},
{45,65,3,2,202},
{47,7,2,1,202},
{47,65,2,1,202},
{48,7,3,1,202},
{48,64,3,1,202},
{49,8,2,1,202},
{49,64,2,1,202},
{50,8,3,2,202},
{50,63,3,2,202},
{52,9,3,1,202},
{52,62,3,1,202},
{53,10,2,1,202},
{53,62,2,1,202},
{54,10,3,1,202},
{54,61,3,1,202},
{55,11,3,1,202},
{55,60,3,1,202},
{56,12,3,1,202},
{56,59,3,1,202},
{57,12,4,1,202},
{57,58,4,1,202},
{58,13,4,1,202},
{58,57,4,1,202},
{59,14,4,1,202},
{59,56,4,1,202},
{60,15,4,1,202},
{60,55,4,1,202},
{61,16,4,1,202},
{61,54,4,1,202},
{62,18,4,1,202},
{62,52,4,1,202},
{63,19,5,1,202},
{63,50,5,1,202},
{64,21,5,1,202},
{64,48,5,1,202},
{65,22,7,1,202},
{65,45,7,1,202},
{66,25,10,1,202},
{66,39,10,1,202},
{67,27,20,1,202},
{68,31,12,1,202},
}

-- ============================================================
-- 圆形启动按钮（像素Logo · v5.3）
-- ============================================================
CreateFloat = function()
    if floatItem and floatItem.btn and IsValidUI(floatItem.btn) then return end

    -- 清理可能残留的旧浮动按钮元素（避免重复叠加）
    if floatItem and floatItem.allElements then
        for _, w in ipairs(floatItem.allElements) do
            if w and IsValidUI(w) then
                pcall(function()
                    w:RemoveFromParent()
                    w:ConditionalBeginDestroy()
                end)
            end
        end
    end
    floatItem = nil

    pcall(function()
        local canvas = GetCanvas()
        if not canvas then return end
        floatItem = { allElements = {}, ringWidgets = {} }

        local function track(w)
            if w and IsValidUI(w) then
                table.insert(floatItem.allElements, w)
            end
            return w
        end

        local fX, fY = 18, 14
        local fW, fH = 62, 62
        local accentBright = AccentBright(2, 1.0)
        local accentMid    = AccentColor(2, 0.55)
        local ringWhite    = FLinearColor(1, 1, 1, 1)
        local sepColor     = FLinearColor(0.012, 0.018, 0.034, 0.96)

        -- ---------- 圆形 Logo（像素画 · RLE 色块渲染） ----------
        local data = _G.U5LogoData
        local pal  = _G.U5LogoPal
        local cell = _G.U5LogoCell or 1.0
        local off  = _G.U5LogoOffset or 6
        local ox, oy = fX - off, fY - off

        if data and pal then
            local cached = {}
            for i = 1, #pal do
                local p = pal[i]
                cached[i] = FLinearColor(p[1], p[2], p[3], 1.0)
            end

            for i = 1, #data do
                local r  = data[i]
                local lv = r[5]
                local col, z, isRGB, isPulse, grow = nil, 11890, false, false, 0.0

                if lv == 201 then
                    -- RGB 动效外发光
                    col, z, isRGB, grow = RGBColor(0.30), 11888, true, 0.0
                elseif lv == 202 then
                    -- 主亮环（hover 时高亮为白色）
                    col, z, grow = accentBright, 11898, 0.40
                elseif lv == 101 then
                    -- 内圈脉冲环
                    col, z, isPulse, grow = accentMid, 11896, true, 0.15
                elseif lv == 103 then
                    -- 分隔暗环
                    col, z, grow = sepColor, 11894, 0.15
                elseif lv >= 1 and lv <= 7 then
                    -- 图像灰度
                    col, z, grow = cached[lv], 11890, 0.40
                end

                if col then
                    local b = Layer(canvas,
                        ox + r[2] * cell, oy + r[1] * cell,
                        r[3] * cell + grow, r[4] * cell + grow,
                        col, z, isRGB, isPulse, 2)
                    if lv == 202 then
                        table.insert(floatItem.ringWidgets, b)
                    end
                    track(b)
                end
            end
        end

        -- ---------- 点击热区 ----------
        pcall(function()
            floatItem.btn = CGame:NewObjectFromPath("/Script/UMG.Button", canvas)
            if floatItem.btn and slua.isValid(floatItem.btn) then
                pcall(function() floatItem.btn:SetColorAndOpacity(C.transparent) end)
                pcall(function() floatItem.btn:SetBackgroundColor(C.transparent) end)
                pcall(function()
                    floatItem.btn:SetWidgetVisibility(UEnums.ESlateVisibility.Visible)
                end)
                local slot = canvas:AddChildToCanvas(floatItem.btn)
                if slot then
                    slot:SetAutoSize(false)
                    slot:SetPosition(FVector2D(fX - 2, fY - 2))
                    slot:SetSize(FVector2D(fW + 4, fH + 4))
                    slot:SetZOrder(12003)
                end
                pcall(function()
                    if floatItem.btn.OnClicked then
                        floatItem.btn.OnClicked:Add(function()
                            pcall(function()
                                if isMenuOpen then
                                    -- 关闭：走关闭动画
                                    isMenuOpen = false
                                    _G.U5AnimateMenuClose()
                                else
                                    -- 打开：如果已构建走打开动画，否则 BuildMenu
                                    isMenuOpen = true
                                    if menuBuilt and bgPanel and IsValidUI(bgPanel) then
                                        _G.U5AnimateMenuOpen()
                                    else
                                        BuildMenu()
                                    end
                                end
                            end)
                        end)
                    end
                    if floatItem.btn.OnHovered then
                        floatItem.btn.OnHovered:Add(function()
                            pcall(function()
                                local fi = _G.U5FloatItem
                                if fi and fi.ringWidgets then
                                    for _, w in ipairs(fi.ringWidgets) do
                                        if w and IsValidUI(w) then
                                            w:SetBrushColor(ringWhite)
                                        end
                                    end
                                end
                            end)
                        end)
                    end
                    if floatItem.btn.OnUnhovered then
                        floatItem.btn.OnUnhovered:Add(function()
                            pcall(function()
                                local fi = _G.U5FloatItem
                                if fi and fi.ringWidgets then
                                    for _, w in ipairs(fi.ringWidgets) do
                                        if w and IsValidUI(w) then
                                            w:SetBrushColor(accentBright)
                                        end
                                    end
                                end
                            end)
                        end)
                    end
                end)
            end
            track(floatItem.btn)
        end)
    end)

    _G.U5FloatItem = floatItem

    if _G.U5BtnConfig and _G.U5BtnConfig.SHOW_FLOAT == 0 then
        if _G.SetU5FloatVisible then _G.SetU5FloatVisible(false) end
    end
end

function _G.SetU5FloatVisible(visible)
    if not floatItem or not floatItem.allElements then return end
    local vis    = visible and UEnums.ESlateVisibility.SelfHitTestInvisible
                         or  UEnums.ESlateVisibility.Collapsed
    local btnVis = visible and UEnums.ESlateVisibility.Visible
                         or  UEnums.ESlateVisibility.Collapsed
    for _, w in ipairs(floatItem.allElements) do
        if w and IsValidUI(w) then
            pcall(function()
                if w == floatItem.btn then
                    w:SetWidgetVisibility(btnVis)
                else
                    w:SetWidgetVisibility(vis)
                end
            end)
        end
    end
end

-- ============================================================
-- U5按钮 菜单注入
-- ============================================================
function _G.InitU5BtnMenu()
    if _G.U5BtnMenuInitialized then return end
    _G.U5BtnMenuInitialized = true

    local LocUtil = _G.LocUtil
    if not LocUtil then LocUtil = require("client.common.LocUtil") end
    if LocUtil and not LocUtil._IsU5BtnHooked then
        local orig = LocUtil.GetLocalizeResStr
        LocUtil.GetLocalizeResStr = function(key)
            if type(key) == "string" and not tonumber(key) then return key end
            return orig(key)
        end
        LocUtil._IsU5BtnHooked = true
    end

    local SettingPageDefine = require("client.logic.NewSetting.SettingPageDefine")
    local SettingCatalog = require("client.logic.NewSetting.SettingCatalog")
    if SettingPageDefine.U5BtnMenu then return end

    local AliasMap = require("client.slua.umg.NewSetting.Item.AliasMap")

    local U5BtnMenu = {
        Key = "U5BtnMenu",
        Text = "U5按钮",
        UIKey = "Setting_Page_Privacy",
        Category = {
            {
                Key = "Cat_U5Btn",
                Text = "U5 浮动按钮",
                Stack = {
                    {
                        Key = "U5B_SHOW_FLOAT",
                        UI = AliasMap.TitleSwitcher,
                        Text = "显示左上角 U5 浮动按钮",
                        GetFunc = function() return _G.U5BtnConfig.SHOW_FLOAT == 1 end,
                        SetFunc = function(_, v)
                            _G.U5BtnConfig.SHOW_FLOAT = v and 1 or 0
                            SaveConfigU5Btn()
                            if _G.SetU5FloatVisible then
                                _G.SetU5FloatVisible(_G.U5BtnConfig.SHOW_FLOAT == 1)
                            end
                            return true
                        end
                    },
                }
            }
        }
    }

    SettingPageDefine.U5BtnMenu = U5BtnMenu
    table.insert(SettingCatalog, SettingPageDefine.U5BtnMenu)

    local UIManager = _G.UIManager
    if UIManager and not UIManager._IsU5BtnHooked then
        local origShow = UIManager.ShowUI
        UIManager.ShowUI = function(config, ...)
            local args = {...}
            if config and config.keyName and
               string.find(string.lower(config.keyName), "setting") then
                local catalog = args[1]
                if type(catalog) == "table" then
                    local found = false
                    for _, p in ipairs(catalog) do
                        if type(p) == "table" and p.Key == "U5BtnMenu" then
                            found = true break
                        end
                    end
                    if not found then
                        table.insert(catalog, SettingPageDefine.U5BtnMenu)
                    end
                end
            end
            return origShow(config, table.unpack(args, 1, select("#", ...)))
        end
        UIManager._IsU5BtnHooked = true
    end
end

-- ============================================================
-- 换局重置
-- ============================================================
local function ResetU5State()
    if bgPanel and IsValidUI(bgPanel) then
        pcall(function()
            bgPanel:RemoveFromParent()
            bgPanel:ConditionalBeginDestroy()
        end)
    end
    if floatItem and floatItem.allElements then
        for _, w in ipairs(floatItem.allElements) do
            if w and IsValidUI(w) then
                pcall(function()
                    w:RemoveFromParent()
                    w:ConditionalBeginDestroy()
                end)
            end
        end
    end
    bgPanel, floatItem, parentCanvas = nil, nil, nil
    menuBuilt, isMenuOpen = false, false
    currentParentTab = 1
    currentSubTab = {1, 1, 1, 1, 1, 1}
    parentTabButtons = {}
    subTabButtons = {{}, {}, {}, {}, {}, {}}
    subTabPanels = {{}, {}, {}, {}, {}, {}}
    subTabScrollBoxes = {{}, {}, {}, {}, {}, {}}
    allWidgets, rgbWidgets, pulseWidgets = {}, {}, {}
    dataDots = {}
    _G.U5Rows = {}
    _G._U5_PerfText, _G._U5_BgLayer, _G._U5_BgPanelStrips = nil, nil, nil
    _G.U5MenuInitialized = false
    _G.U5_MAIN_TIMER, _G.AIMTOUCH_TIMER, _G.FOVCIRCLE_TIMER = nil, nil, nil
    _G.AimLockTarget, _G.AimBotCurrentTarget = nil, nil
    _G.U5FloatItem, _G._U5_CrumbText = nil, nil
    _G.U5UIState.autoCentered = false
    _G.U5UIState.animating = false
    pcall(_G.CleanUpFovCircleOverlay)
    print("[U5] 状态已重置（换局/重连）")
end

-- ============================================================
-- 初始化入口
-- ============================================================
function _G.InitU5Menu()
    if _G.U5MenuInitialized then return end
    _G.U5MenuInitialized = true
    InitAntiCheatBypass()
    pcall(function()
        local pc = slua_GameFrontendHUD and
            slua_GameFrontendHUD:GetPlayerController()
        if pc then
            CreateFloat()
            pc:AddGameTimer(3, true, function()
                if not floatItem or not floatItem.btn or not IsValidUI(floatItem.btn) then
                    floatItem = nil
                    CreateFloat()
                end
            end)
        end
    end)
end

-- ============================================================
-- 启动
-- ============================================================
local lastRestartAttempt = 0
local function StartMainLoop()
    local pc = slua_GameFrontendHUD:GetPlayerController()
    if not Valid(pc) then return false end
    if _G.U5_MAIN_TIMER and Valid(_G.U5_MAIN_TIMER) then return true end
    local now = os.clock()
    if now - lastRestartAttempt < 5.0 then return false end
    lastRestartAttempt = now

    ResetU5State()
    LoadConfig()
    pcall(_G.InitU5Menu)

    pcall(StartAimTouchTimer)
    pcall(StartFovCircleTimer)
    pcall(StartFovCircleSelfHeal)

    _G.U5_MAIN_TIMER = pc
    pc:AddGameTimer(1.5, true, MainTick)
    return true
end

local function OnGameStart()
    InitAutoSave()
    LoadConfig()
    if _G.ConfigAutoSave and not _G.ConfigAutoSave.Started then
        _G.ConfigAutoSave:StartLoop()
    end
    pcall(_G.InitU5Menu)
    pcall(_G.InitU5BtnMenu)
    pcall(InitNativeESPConfig)
    pcall(StartFovCircleSelfHeal)

    local pc = slua_GameFrontendHUD:GetPlayerController()
    if Valid(pc) then
        pc:AddGameTimer(2, false, function()
            StartMainLoop()
        end)
    end
end

OnGameStart()

print("======================================")
print("U5 综合菜单 v5.4 已加载")
print("霓虹圆形Logo按钮 · 菜单淡入滑入过渡 · 关闭淡出滑出")
print("操作：点击按钮开/关 | 标题栏拖拽 | 搜索过滤 | 双击数值输入 | P1-3单击加载双击保存")
print("长按左上 U5 logo 5 次切换背景透明度")
print("======================================")

local M = {}
function M.OnCtor(self) end
function M.OnPost(self) self:OnAdvance(); self:OnTick(0) end
function M.OnTick(self, dt) end
function M.OnAdvance(self)
    pcall(function()
        if _G.U5_MAIN_TIMER and not Valid(_G.U5_MAIN_TIMER) then
            StartMainLoop()
        end
        if floatItem and floatItem.btn and not IsValidUI(floatItem.btn) then
            floatItem = nil
            CreateFloat()
        end
        if bgPanel and not IsValidUI(bgPanel) then
            bgPanel = nil
            menuBuilt = false
        end
    end)
end
function M.OnBeginPlay(self)
    pcall(_G.InitU5Menu)
    pcall(_G.InitU5BtnMenu)
    pcall(StartAimTouchTimer)
    pcall(StartFovCircleTimer)
    pcall(StartFovCircleSelfHeal)
end
return 