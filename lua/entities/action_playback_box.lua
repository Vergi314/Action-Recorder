---@diagnostic disable: undefined-global
AddCSLuaFile()
ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Action Playback Box"
ENT.Category = "Utility"
ENT.Spawnable = false
ENT.SoundPath = "buttons/button1.wav"
-- Global playback timer
local GLOBAL_PLAYBACK_TIMER = "ActionRecorder_GlobalPlayback"
local GLOBAL_TIMER_INTERVAL = AR_FRAME_INTERVAL
local ActivePlaybackBoxes = {}
function ENT:Initialize()
    self:SetSolid(SOLID_VPHYSICS)
    if SERVER then self:SetUseType(SIMPLE_USE) end
    self.PlaybackData = {}
    self.PlaybackSpeed = 1
    self.LoopMode = AR_LOOP_MODE.NO_LOOP
    self.PlaybackDirection = AR_PLAYBACK_DIRECTION.FORWARD
    self.PlaybackType = AR_PLAYBACK_TYPE.ABSOLUTE
    self.Easing = "None"
    self.EasingAmplitude = 1
    self.EasingFrequency = 1
    self.EasingInvert = false
    self.EasingOffset = 0
    self.status = AR_ANIMATION_STATUS.NOT_STARTED
    self.lastStatus = AR_ANIMATION_STATUS.NOT_STARTED
    self.BoxID = "Box"
    self.NumpadKey = self.NumpadKey or 5
    self.IsActivated = false
    self.ShouldSmoothReturn = false
    self.PhysicslessTeleport = false
    self.ReversePlayback = false
    self.WasReversed = false
    if SERVER and not self:GetNWString("OwnerName", nil) then self:SetNWString("OwnerName", "Unknown") end
    if SERVER then
        self:SetupNumpad()
        ActionRecorder.Wire.SetupEntity(self)
    end
    --ARLog("Done initializing" )
end

function ENT:SetupNumpad()
    if not IsValid(self:GetOwner()) or not self.NumpadKey then return end
    if self.NumpadBind then
        numpad.Remove(self.NumpadBind)
        self.NumpadBind = nil
    end

    if self.NumpadUpBind then
        numpad.Remove(self.NumpadUpBind)
        self.NumpadUpBind = nil
    end

    self.NumpadBind = numpad.OnDown(self:GetOwner(), self.NumpadKey, "ActionRecorder_Playback", self)
    self.NumpadUpBind = numpad.OnUp(self:GetOwner(), self.NumpadKey, "ActionRecorder_Playback_Release", self)
end

function ENT:OnRemove()
    self:StopPlayback(true)
    if self.NumpadBind then
        numpad.Remove(self.NumpadBind)
        self.NumpadBind = nil
    end

    if self.NumpadUpBind then
        numpad.Remove(self.NumpadUpBind)
        self.NumpadUpBind = nil
    end
end

function ENT:SetModelPath(model)
    if not model or model == "" or not util.IsValidModel(model) then model = "models/props_c17/oildrum001.mdl" end
    if SERVER then self:SetModel(model) end
end

function ENT:SetPlaybackData(data, entitiesConstants)
    if not data or type(data) ~= "table" or next(data) == nil then
        ARLog("SetPlaybackData Attempt to set Empty data ", data)
        return
    end

    --ARLog("SetPlaybackData length ", #data)
    self.PlaybackData = {}
    self.AnimationInfo = {}
    self.EntitiesConstants = entitiesConstants or {}
    local direction = AR_PLAYBACK_DIRECTION.FORWARD
    if self.PlaybackSpeed < 0 then direction = AR_PLAYBACK_DIRECTION.REVERSE end
    for id, frames in pairs(data) do
        if not frames or 0 == #frames then
            ARLog("attempt to setplayback entity with zero frames skipping")
            continue --just ignore zero frames recordings
        end

        self.PlaybackData[id] = frames
        local ent = Entity(id)
        self.AnimationInfo[id] = {
            frameCount = #frames,
            direction = direction,
            status = AR_ANIMATION_STATUS.NOT_STARTED,
            currentFrameIndex = 1,
            initialPos = nil,
            initialAng = nil,
            model = IsValid(ent) and ent:GetModel() or (self.EntitiesConstants[id] and self.EntitiesConstants[id].model),
            class = IsValid(ent) and ent:GetClass() or (self.EntitiesConstants[id] and self.EntitiesConstants[id].class),
            entIndex = id
        }
    end

    self.status = AR_ANIMATION_STATUS.NOT_STARTED
end

function ENT:SetPlaybackSettings(speed, loopMode, playbackType, easing, easing_amplitude, easing_frequency, easing_invert, easing_offset, physicsless, freezeOnEnd, reversePlayback)
    self.PlaybackSpeed = speed or 1
    self.LoopMode = loopMode or AR_LOOP_MODE.NO_LOOP
    self.PlaybackType = playbackType or AR_PLAYBACK_TYPE.ABSOLUTE
    self.Easing = easing or "Linear"
    self.EasingAmplitude = easing_amplitude or 1
    self.EasingFrequency = easing_frequency or 1
    self.EasingInvert = easing_invert or false
    self.EasingOffset = easing_offset or 0
    self.ReversePlayback = reversePlayback or false
    self.freezeOnEnd = freezeOnEnd or false
    if SERVER then
        -- Update networked variables
        self:SetNWInt("LoopMode", self.LoopMode)
    end
end

function ENT:SetBoxID(id)
    self.BoxID = id or "Box"
    if SERVER then self:SetNWString("BoxID", self.BoxID) end
end

function ENT:SetOwnerName(name)
    if SERVER then self:SetNWString("OwnerName", name or "Unknown") end
end

function ENT:SetSoundPath(soundpath)
    self.SoundPath = soundpath
end

function ENT:SetPhysicslessTeleport(state)
    self.PhysicslessTeleport = tobool(state)
    if SERVER then self:SetNWBool("PhysicslessTeleport", self.PhysicslessTeleport) end
end

function ENT:UpdateSettings(speed, loopMode, playbackType, model, boxid, soundpath, easing, easing_amplitude, easing_frequency, easing_invert, easing_offset, physicsless, freezeOnEnd, reversePlayback)
    self:StopPlayback()
    self:SetPlaybackSettings(speed, loopMode, playbackType, easing, easing_amplitude, easing_frequency, easing_invert, easing_offset, physicsless, freezeOnEnd, reversePlayback)
    self:SetModelPath(model)
    self:SetBoxID(boxid)
    self:SetSoundPath(soundpath)
    self:SetPhysicslessTeleport(physicsless)
    self:SetNWInt("LoopMode", loopMode or 0)
    self:SetupNumpad()
    self:StartPlayback()
end

function ENT:Use(activator, caller)
    if not self.PlaybackData then return end
    self:EmitSound(self.SoundPath or "buttons/button3.wav")
    self:StartPlayback(false)
end

local function IsPropControlledByOtherBox(prop, myBox)
    for _, box in pairs(ents.FindByClass("action_playback_box")) do
        if IsValid(box) and box ~= myBox and box.status == AR_ANIMATION_STATUS.PLAYING and istable(box.PlaybackData) and box.BoxID ~= myBox.BoxID then
            for k, _ in pairs(box.PlaybackData) do
                if k == prop:EntIndex() then return true end
            end
        end
    end
    return false
end

function ENT:StopPlayback(forceReturn)
    if self.status ~= AR_ANIMATION_STATUS.PLAYING and not forceReturn then return end
    if self.LoopMode == AR_LOOP_MODE.NO_LOOP and not forceReturn then
        self.status = AR_ANIMATION_STATUS.SMOOTH_RETURN
        self.SmoothReturnStartTime = CurTime()
    else
        self.status = AR_ANIMATION_STATUS.FINISHED
    end

    self.IsActivated = false
    -- Remove this box from the active playback boxes
    ActivePlaybackBoxes[self] = nil
    -- If no boxes are playing, remove the global timer
    if table.IsEmpty(ActivePlaybackBoxes) then timer.Remove(GLOBAL_PLAYBACK_TIMER) end
end

function ENT:ReverseFrames()
    -- Reverse the frames array for all entities
    for entIndex, frames in pairs(self.PlaybackData or {}) do
        local reversedFrames = {}
        for i = #frames, 1, -1 do
            table.insert(reversedFrames, frames[i])
        end

        self.PlaybackData[entIndex] = reversedFrames
    end

    self.WasReversed = not self.WasReversed
end

function ENT:ProcessSmoothReturn()
    local smoothReturnDuration = 0.5 -- seconds
    local progress = (CurTime() - self.SmoothReturnStartTime) / smoothReturnDuration
    if progress >= 1 then
        self.status = AR_ANIMATION_STATUS.FINISHED
        return
    end

    for entIndex, info in pairs(self.AnimationInfo or {}) do
        local ent = Entity(entIndex)
        if IsValid(ent) then
            local startPos = ent:GetPos()
            local startAng = ent:GetAngles()
            local targetPos = info.initialPos
            local targetAng = info.initialAng
            local newPos = LerpVector(progress, startPos, targetPos)
            local newAng = LerpAngle(progress, startAng, targetAng)
            ent:SetPos(newPos)
            ent:SetAngles(newAng)
        end
    end
end

function ENT:StartPlayback()
    --ARLog("StartPlayback called")
    --ARLog("PlaybackData contains: " .. table.Count(self.PlaybackData or {}) .. " entities")
    -- Check if we need to reverse the frames
    local shouldReverse = self.ReversePlayback
    if shouldReverse and not self.WasReversed then
        self:ReverseFrames()
    elseif not shouldReverse and self.WasReversed then
        self:ReverseFrames() -- Reverse again to get back to original
    end

    -- Capture initial positions/angles when playback starts
    if self.status ~= AR_ANIMATION_STATUS.PLAYING then -- Only capture if not already playing
        for entIndex, frames in pairs(self.PlaybackData or {}) do
            local ent = Entity(entIndex)
            if IsValid(ent) then
                local info = self.AnimationInfo[entIndex]
                if info then
                    info.initialPos = ent:GetPos()
                    ARLog("Entity " .. entIndex .. " initial pos: ", info.initialPos)
                    info.initialAng = ent:GetAngles()
                    ARLog("Entity " .. entIndex .. " frame count: ", info.frameCount)
                end
            end
        end
    end

    self.LastFrameTime = CurTime()
    self.status = AR_ANIMATION_STATUS.PLAYING
    self.PlaybackDirection = AR_PLAYBACK_DIRECTION.FORWARD
    self.IsActivated = true
    -- Add this box to the active playback boxes
    ActivePlaybackBoxes[self] = true
    for _, info in pairs(self.AnimationInfo) do
        info.status = AR_ANIMATION_STATUS.PLAYING
        info.currentFrameIndex = self.PlaybackSpeed >= 0 and 1 or info.frameCount
        info.direction = self.PlaybackSpeed >= 0 and self.PlaybackDirection or -1 * self.PlaybackDirection
        info.LastMoveTime = CurTime()
        info.IsOneTimeSmoothReturn = false
    end

    -- Create the global timer if it doesn't exist
    if not timer.Exists(GLOBAL_PLAYBACK_TIMER) then
        --ARLog("Creating global timer")
        timer.Create(GLOBAL_PLAYBACK_TIMER, GLOBAL_TIMER_INTERVAL, 0, function()
            for box, _ in pairs(ActivePlaybackBoxes) do
                if IsValid(box) then
                    box:ProcessPlayback()
                else
                    ARLog("We have an invalid box")
                end
            end
        end)
    end

    -- Initialize playback for all entities
    ARLog("Initializing playback for " .. table.Count(self.PlaybackData or {}) .. " entities")
    for entIndex, _ in pairs(self.PlaybackData or {}) do
        ARLog("Setting up entity " .. entIndex)
        self:SetupEntityPlayback(entIndex)
    end

    ARLog("Finished StartPlayback")
end

--- This function assumes all entities have same number of frames
--TODO this could be optimized by storing the frames count in the box object when recording is done
function ENT:getFramesCount()
    -- Legacy function - use GetMaxFrames() instead
    return self:GetMaxFrames()
end

function ENT:GetCurrentFrameIndex()
    -- Return the minimum frame across all animated entities
    local minFrame = math.huge
    for _, info in pairs(self.AnimationInfo or {}) do
        if info and info.currentFrameIndex then
            minFrame = math.min(minFrame, info.currentFrameIndex)
            --ARLog("min frame is ", minFrame)
        end
    end
    return minFrame == math.huge and 1 or minFrame
end

function ENT:GetMaxFrames()
    -- Return the maximum frame count across all entities
    local maxFrames = 0
    for _, info in pairs(self.AnimationInfo or {}) do
        if info and info.frameCount then maxFrames = math.max(maxFrames, info.frameCount) end
    end
    return maxFrames
end

function ENT:StopPlaybackIfNeeded()
    local allEntitiesFinished = true
    for _, info in pairs(self.AnimationInfo or {}) do
        if info.status ~= AR_ANIMATION_STATUS.FINISHED then
            allEntitiesFinished = false
            break
        end
    end

    if allEntitiesFinished then self:StopPlayback() end
end

function ENT:freezeEntityIfNeeded(info)
    if not self.freezeOnEnd then return end
    local ent = Entity(info.entIndex)
    if not IsValid(ent) then return end
    local phys = ent:GetPhysicsObject()
    if not IsValid(phys) then return end
    phys:EnableMotion(false)
end

function ENT:advanceFrames(amount, info)
    --ARLog("advanceFrames called: amount=" .. amount .. ", frameCount=" .. frameCount .. ", currentIndex=" .. currentFrameIndex)
    local currentFrameIndex = info.currentFrameIndex
    local frameCount = info.frameCount
    if frameCount <= 1 then
        ARLog("Only one frame available, marking entity as finished.")
        return -1 -- Mark as finished to stop processing
    end

    local atStart = currentFrameIndex == 1
    local atEnd = currentFrameIndex == frameCount
    local nextFrameIndex = currentFrameIndex
    local direction = info.direction
    -- Log basic information
    -- ARLog("direction:", direction, "atStart:", atStart, "atEnd:", atEnd, "frameCount:", frameCount)
    if direction > 0 then
        -- ARLog("Positive direction detected")
        if not atEnd then
            --ARLog("Not at end, incrementing index")
            nextFrameIndex = math.min(nextFrameIndex + amount, frameCount)
        else
            --ARLog("At end, handling loop modes")
            if self.LoopMode == AR_LOOP_MODE.NO_LOOP then
                --ARLog("No loop mode, entity finished")
                info.status = AR_ANIMATION_STATUS.FINISHED
                self:freezeEntityIfNeeded(info)
                return -1
            elseif self.LoopMode == AR_LOOP_MODE.PING_PONG then
                --ARLog("Ping pong mode, reversing direction")
                info.direction = info.direction * -1
                nextFrameIndex = frameCount - 1
            elseif self.LoopMode == AR_LOOP_MODE.LOOP then
                ARLog("Loop mode, resetting to start")
                nextFrameIndex = 1
            elseif self.LoopMode == AR_LOOP_MODE.NO_LOOP_SMOOTH then
                --ARLog("No Loop Smooth mode, reversing direction for one-time return")
                info.direction = info.direction * -1
                info.IsOneTimeSmoothReturn = true
                nextFrameIndex = frameCount - 1
            else
                ARLog("Unsupported Loop mode in advanceFrames")
            end
        end
    else -- direction < 0 case
        -- ARLog("Negative direction detected")
        if not atStart then
            --ARLog("Not at start, decrementing index")
            nextFrameIndex = math.max(1, nextFrameIndex - amount)
        else
            --ARLog("At start, handling loop modes")
            if self.LoopMode == AR_LOOP_MODE.NO_LOOP then
                ARLog("No loop mode, entity finished")
                info.status = AR_ANIMATION_STATUS.FINISHED
                self:freezeEntityIfNeeded(info)
                return -1
            elseif self.LoopMode == AR_LOOP_MODE.PING_PONG then
                --ARLog("Ping pong mode, reversing direction")
                info.direction = info.direction * -1
                nextFrameIndex = 2
            elseif self.LoopMode == AR_LOOP_MODE.LOOP then
                --ARLog("Loop mode, resetting to end")
                nextFrameIndex = frameCount
            elseif self.LoopMode == AR_LOOP_MODE.NO_LOOP_SMOOTH and info.IsOneTimeSmoothReturn then
                --ARLog("No Loop Smooth mode, finished one-time return")
                info.status = AR_ANIMATION_STATUS.FINISHED
                self:freezeEntityIfNeeded(info)
                return -1 -- Animation finished
            end
        end
    end
    --ARLog("advanceFrames calculated nextFrameIndex:", nextFrameIndex)
    return nextFrameIndex
end

function ENT:GetSpeed(currentFrameIndex, frameCount)
    --ARLog("GetSpeed called " , self.Easing)
    -- Calculate progress for THIS specific entity (0 to 1)
    local progress = currentFrameIndex / frameCount
    local minSpeed = 0.1
    local speed = minSpeed
    if not self.Easing or self.Easing == "None" then
        --ARLog("Using no easing, returning base speed: " .. self.PlaybackSpeed)
        return self.PlaybackSpeed
    end

    local easing_func = ActionRecorder.EasingFunctions[self.Easing]
    if not easing_func then
        ARLog("Easing function not found ", self.Easing)
        speed = self.PlaybackSpeed
    else
        local y = easing_func(progress, self.EasingAmplitude, self.EasingFrequency, self.EasingInvert, self.EasingOffset)
        speed = self.PlaybackSpeed * y
        --ARLog("Easing function value for , is and speed ", progress, y, speed)
    end

    if speed < minSpeed then speed = minSpeed end
    --ARLog("Easing calculation - Current: " .. speed)
    return speed
end

function ENT:calculateNextFrame(info)
    local currentFrameIndex = info.currentFrameIndex
    local framesCount = info.frameCount
    local lastMoveTime = info.LastMoveTime
    local speed = self:GetSpeed(currentFrameIndex, framesCount)
    --ARLog("calculateNextFrame: speed=" .. speed .. ", currentFrame=" .. currentFrameIndex .. ", totalFrames=" .. framesCount)
    if speed == 0 then
        ARLog("Speed is zero for ") -- TODO add the box id in the message
        return 1 -- move object at first frame if he set speed to 0
    end

    local moveTimeInterval = GLOBAL_TIMER_INTERVAL / math.abs(speed) --dividing with a num less then 1 will increase the numerator
    local now = CurTime()
    local timeSinceLastMove = now - lastMoveTime
    -- if speed is small we might not need to move to next frame
    if math.abs(speed) < 1 then
        --ARLog("speed < 1: " .. speed .. ", timeSinceLastMove: " .. timeSinceLastMove .. ", moveTimeInterval: " .. moveTimeInterval)
        if timeSinceLastMove < moveTimeInterval then
            -- Return decimal frame index for smooth interpolation
            local progress = timeSinceLastMove / moveTimeInterval
            --local decimalFrameIndex = currentFrameIndex + progress
            --ARLog("returning decimal frame index " .. decimalFrameIndex)
            return self:advanceFrames(progress, info)
        else -- we need to advance 1 frame
            --ARLog("advancing 1 frame from " .. currentFrameIndex)
            return self:advanceFrames(1, info)
        end
    else --case speed is greate then 1 in abs value
        local framesToMove = math.floor(timeSinceLastMove / moveTimeInterval)
        return self:advanceFrames(framesToMove, info)
    end
end

function ENT:SetupEntityPlayback(entIndex)
    ARLog("SetupEntityPlayback for entity " .. entIndex)
    local ent = Entity(entIndex)
    if not IsValid(ent) then return end
    --if IsPropControlledByOtherBox(ent, self) then return end -- This is only for replaying one box at a time.
    local phys = ent:GetPhysicsObject()
    if not IsValid(phys) then return end
    local frames = self.PlaybackData[entIndex]
    local info = self.AnimationInfo[entIndex]
    local frameCount = info.frameCount
    if frameCount == 0 then return end
    phys:EnableMotion(true)
    ent:SetCollisionGroup(COLLISION_GROUP_NONE)
    local i = info.currentFrameIndex
    local basePos = Vector(0, 0, 0)
   if self.PlaybackType == AR_PLAYBACK_TYPE.RELATIVE and frames[1] and frames[1].pos and info.initialPos then
        basePos = info.initialPos - frames[1].pos
    end
    if ent.IsBeingPlayedBack and ent.PlaybackBox and ent.PlaybackBox ~= self then
        ent.IsBeingPlayedBack = false
        ent.PlaybackBox = nil
    end

    if frames[i].pos and frames[i].ang then
        ent.TargetPos = frames[i].pos + basePos
        ent.TargetAng = frames[i].ang
        ARLog("Entity " .. entIndex .. " target pos set to: " .. tostring(ent.TargetPos))
        -- Immediately apply the first frame position
        self:ApplyFrameData(ent, frames[i], basePos, true)
    else
        ent.TargetPos = ent:GetPos()
        ent.TargetAng = ent:GetAngles()
        ARLog("Entity " .. entIndex .. " no frame data, using current pos: " .. tostring(ent.TargetPos))
    end

    ent.IsBeingPlayedBack = true
    ent.PlaybackBox = self
end

function ENT:calculateDirection()
    return self.PlaybackDirection * (self.PlaybackSpeed < 0 and -1 or 1)
end

function interpolateFrame(frames, decimalIndex, direction)
    if math.floor(decimalIndex) == decimalIndex then return frames[decimalIndex] end
    local frameIndex = math.floor(math.abs(decimalIndex))
    local alpha = decimalIndex - frameIndex
    -- Get current and next frame indices based on direction
    local currentFrameIndex = frameIndex
    local nextFrameIndex
    if direction > 0 then
        nextFrameIndex = math.min(frameIndex + 1, #frames)
    else
        nextFrameIndex = math.max(frameIndex - 1, 1)
    end

    local currentFrame = frames[currentFrameIndex]
    local nextFrame = frames[nextFrameIndex]
    if not currentFrame or not nextFrame then return currentFrame or nextFrame end
    -- Clone current frame
    local interpolatedFrame = table.Copy(currentFrame)
    -- Interpolate position
    if currentFrame.pos and nextFrame.pos then interpolatedFrame.pos = LerpVector(alpha, currentFrame.pos, nextFrame.pos) end
    -- Interpolate angles
    if currentFrame.ang and nextFrame.ang then interpolatedFrame.ang = LerpAngle(alpha, currentFrame.ang, nextFrame.ang) end
    -- Interpolate color if present
    if currentFrame.color and nextFrame.color then interpolatedFrame.color = Color(Lerp(alpha, currentFrame.color.r, nextFrame.color.r), Lerp(alpha, currentFrame.color.g, nextFrame.color.g), Lerp(alpha, currentFrame.color.b, nextFrame.color.b), Lerp(alpha, currentFrame.color.a, nextFrame.color.a)) end
    return interpolatedFrame
end

function changeKey(oldKey, newKey, targetTable)
    if oldKey == newKey then -- Do nothing if keys are the same
        return
    end

    -- Check if the old key exists in the table.
    -- If it doesn't, there's nothing to change.
    if targetTable[oldKey] ~= nil then
        -- 1. Get the value from the old key.
        local valueToMove = targetTable[oldKey]
        -- 2. Assign that value to the new key.
        targetTable[newKey] = valueToMove
        -- 3. Remove the old key.
        targetTable[oldKey] = nil
    else
        -- Optionally, you can add an error message or
        -- a print statement to indicate the key wasn't found.
        print("Error: The old key '" .. tostring(oldKey) .. "' does not exist in the table.")
    end
end

function ENT:ProcessPlayback()
    if self.status == AR_ANIMATION_STATUS.SMOOTH_RETURN then
        self:ProcessSmoothReturn()
        return
    end

    if self.status ~= AR_ANIMATION_STATUS.PLAYING then return end
    local now = CurTime()
    local entityKeys = {}
    for k in pairs(self.PlaybackData or {}) do
        table.insert(entityKeys, k)
    end

    for _, entIndex in ipairs(entityKeys) do
        if not self.PlaybackData[entIndex] then continue end
        local frames = self.PlaybackData[entIndex]
        local ent = Entity(entIndex)
        local currentEntIndex = entIndex
        if not IsValid(ent) then
            local model = self.AnimationInfo[entIndex].model
            local class = self.AnimationInfo[entIndex].class
            if not class or not model then continue end
            local initialPos = nil
            for _, frame in ipairs(frames) do
                if frame.pos then
                    initialPos = frame.pos
                    break
                end
            end

            if not initialPos then continue end
            ent = ents.Create(class)
            if not IsValid(ent) then continue end
            ent:SetModel(model)
            ent:SetPos(initialPos)
            ent:Spawn()
            local newEntId = ent:EntIndex()
            changeKey(entIndex, newEntId, self.AnimationInfo)
            changeKey(entIndex, newEntId, self.PlaybackData)
            currentEntIndex = newEntId
            frames = self.PlaybackData[currentEntIndex]
        end

        local phys = ent:GetPhysicsObject()
        if not IsValid(phys) then continue end
        local info = self.AnimationInfo[currentEntIndex]
        if not info then continue end
        if info.status == AR_ANIMATION_STATUS.FINISHED then continue end
        local frameCount = info.frameCount
        if frameCount == 0 then continue end
        local frameIndex = self:calculateNextFrame(info)
        if frameIndex == info.currentFrameIndex then continue end
        if frameIndex == -1 then
            self:StopPlaybackIfNeeded()
            continue
        end

        local frame
        if math.floor(frameIndex) == frameIndex then
            frame = frames[frameIndex]
        else
            local direction = self:calculateDirection()
            frame = interpolateFrame(frames, frameIndex, direction)
        end

        if frame then
            local basePos = Vector(0, 0, 0)
            if self.PlaybackType == AR_PLAYBACK_TYPE.RELATIVE and frame.pos then if info.initialPos and frames[1] and frames[1].pos then basePos = info.initialPos - frames[1].pos end end
            self:ApplyFrameData(ent, frame, basePos, false)
            info.LastMoveTime = now
        end

        info.currentFrameIndex = frameIndex
    end

    self.LastFrameTime = now
end

function ENT:ApplyFrameData(ent, frame, basePos, teleport)
    -- Apply position and angle changes
    if frame.pos and frame.ang then
        local targetPos = frame.pos + basePos
        local targetAng = frame.ang
        local phys = ent:GetPhysicsObject()
        if not IsValid(phys) then
            ent:SetPos(targetPos)
            ent:SetAngles(targetAng)
        elseif teleport then
            ent:SetPos(targetPos)
            ent:SetAngles(targetAng)
            phys:Wake()
        else
            local params = {
                pos = targetPos,
                angle = targetAng,
                maxspeed = 10000,
                maxangular = 10000,
                maxspeeddamp = 10000,
                maxangulardamp = 10000,
                dampfactor = 1,
                teleportdistance = self.PhysicslessTeleport and 0.1 or 0,
                deltaTime = GLOBAL_TIMER_INTERVAL
            }

            phys:Wake()
            phys:ComputeShadowControl(params)
        end
    else
        ARLog("ApplyFrameData NO pos OR angle", frame.pos, frame.ang)
    end

    -- Apply visual changes
    if frame.material then ent:SetMaterial(frame.material) end
    if frame.color then ent:SetColor(frame.color) end
    if frame.renderfx then ent:SetRenderFX(frame.renderfx) end
    if frame.rendermode then ent:SetRenderMode(frame.rendermode) end
    if frame.skin then ent:SetSkin(frame.skin) end
    if frame.bodygroups then
        for id, val in pairs(frame.bodygroups) do
            ent:SetBodygroup(id, val)
        end
    end

    if frame.ignited ~= nil then
        if frame.ignited then
            ent:Ignite(30, 0)
        else
            ent:Extinguish()
        end
    end

    if frame.collisiongroup ~= nil then ent:SetCollisionGroup(frame.collisiongroup) end
end

if CLIENT then
    function ENT:Initialize()
    end

    function ENT:OnRemove()
    end

    function ENT:Draw()
        self:DrawModel()
        local id = self:GetNWString("BoxID", "") or ""
        local ownerName = self:GetNWString("OwnerName", "Unknown") or "Unknown"
        if not IsValid(LocalPlayer()) or not self:GetPos() then return end
        local distSqr = LocalPlayer():GetPos():DistToSqr(self:GetPos())
        if id == "" or distSqr > (300 * 300) then return end
        local pos = self:GetPos() + Vector(0, 0, 40)
        local ang = Angle(0, LocalPlayer():EyeAngles().y - 90, 90)
        cam.Start3D2D(pos, ang, 0.2)
        local useRainbow = self:GetNWBool("LabelRainbow", false)
        local backgroundColor
        if useRainbow then
            local hue = (CurTime() * 100) % 360
            backgroundColor = HSVToColor(hue, 1, 1)
            backgroundColor.a = self:GetNWInt("LabelColorA", 255)
        else
            local r = self:GetNWInt("LabelColorR", 255)
            local g = self:GetNWInt("LabelColorG", 255)
            local b = self:GetNWInt("LabelColorB", 255)
            local a = self:GetNWInt("LabelColorA", 255)
            backgroundColor = Color(r, g, b, a)
        end

        local fontID = "DermaLarge"
        local paddingX = 25
        surface.SetFont(fontID)
        local idTextWidth = surface.GetTextSize(id)
        local boxWidth = math.max(200, idTextWidth + paddingX * 2)
        local boxHeight = 70
        draw.RoundedBox(8, -boxWidth / 2, -boxHeight / 2, boxWidth, boxHeight, backgroundColor)
        local iconSize = 32
        local iconX = -boxWidth / 2 + 10
        local iconY = -iconSize / 2 - 10
        local boxIconPath = "icon16/box.png"
        local boxMat = Material(boxIconPath)
        if boxMat and not boxMat:IsError() then
            surface.SetDrawColor(255, 255, 255, 255)
            surface.SetMaterial(boxMat)
            surface.DrawTexturedRect(iconX, iconY, iconSize, iconSize)
        end

        local textStartX = iconX + iconSize + 10
        draw.SimpleText(id, fontID, textStartX, -10, Color(0, 0, 0, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local AR_LOOP_MODE = {
            NO_LOOP = 0,
            LOOP = 1,
            PING_PONG = 2,
            NO_LOOP_SMOOTH = 3,
        }

        local loopMode = self:GetNWInt("LoopMode", AR_LOOP_MODE.NO_LOOP)
        local loopIconPath = "icon16/box.png"
        if loopMode == AR_LOOP_MODE.NO_LOOP then
            loopIconPath = "icon16/arrow_right.png"
        elseif loopMode == AR_LOOP_MODE.LOOP then
            loopIconPath = "icon16/arrow_refresh.png"
        elseif loopMode == AR_LOOP_MODE.PING_PONG then
            loopIconPath = "icon16/arrow_rotate_clockwise.png"
        elseif loopMode == AR_LOOP_MODE.NO_LOOP_SMOOTH then
            loopIconPath = "icon16/arrow_redo.png"
        end

        local loopMat = Material(loopIconPath)
        if loopMat and not loopMat:IsError() then
            local loopIconSize = 32
            local loopIconX = iconX
            local loopIconY = iconY + iconSize + -3
            surface.SetDrawColor(255, 255, 255, 255)
            surface.SetMaterial(loopMat)
            surface.DrawTexturedRect(loopIconX, loopIconY, loopIconSize, loopIconSize)
        end

        local fontOwner = "DermaDefault"
        surface.SetFont(fontOwner)
        local ownerText = "(" .. ownerName .. ")"
        local ownerTextWidth = surface.GetTextSize(ownerText)
        local ownerX = 0
        local ownerY = 20
        draw.SimpleTextOutlined(ownerText, fontOwner, ownerX, ownerY, Color(0, 255, 0, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 2, Color(0, 0, 0, 180))
        local userMat = Material("icon16/user.png")
        local avatarSize = 24
        local avatarX = ownerX + (ownerTextWidth / 2) + 5
        local avatarY = ownerY - avatarSize / 2 + 5
        surface.SetDrawColor(255, 255, 255, 255)
        surface.SetMaterial(userMat)
        surface.DrawTexturedRect(avatarX, avatarY, avatarSize, avatarSize)
        cam.End3D2D()
    end
end

if SERVER then
    numpad.Register("ActionRecorder_Playback", function(ply, ent)
        if not IsValid(ply) or not IsValid(ent) then return end
        if ent:GetClass() ~= "action_playback_box" then return end
        if ent:GetOwner() ~= ply then return end
        ent:EmitSound(ent.SoundPath or "buttons/button3.wav")
        ent:StartPlayback(false)
    end)

    numpad.Register("ActionRecorder_Playback_Release", function(ply, ent)
        if not IsValid(ent) then return end
        if ent:GetNWString("OwnerName", "") ~= ply:Nick() then return end
    end)

    if WireLib then duplicator.RegisterEntityClass("action_playback_box", WireLib.MakeWireEnt, "Data") end
end

function ENT:OnDuplicated()
    -- Re-setup wire integration when entity is duplicated
    if WireLib then
        timer.Simple(0.1, function()
            if IsValid(self) then
                --ARLog("Re-initializing wire integration after duplication")
                ActionRecorder.Wire.SetupEntity(self)
            end
        end)
    end
end

function ENT:TriggerInput(iname, value)
    if not WireLib then return end
    local handlers = {
        ["Play"] = function(val)
            if val ~= 0 then
                self:StartPlayback(false)
            else
                self:StopPlayback(false)
            end
        end,
        ["Stop"] = function(val) if val ~= 0 then self:StopPlayback(false) end end,
        ["PlaybackSpeed"] = function(val) self.PlaybackSpeed = math.Clamp(val, -10, 10) end,
        ["LoopMode"] = function(val)
            local validMode = ActionRecorder.Wire.ValidateLoopMode(val)
            if validMode then
                self.LoopMode = validMode
            else
                ActionRecorder.Wire.Error(self, "Invalid loop mode: " .. tostring(val))
            end
        end,
        ["Reset"] = function(val) if val ~= 0 then self:ResetPlayback() end end,
        ["SetFrame"] = function(val)
            if 0 == val then return end
            --ARLog("SetFrame input val is ", val)
            self:SetCurrentFrame(math.max(1, val))
        end
    }

    local handler = handlers[iname]
    if handler then
        handler(value)
    else
        ActionRecorder.Wire.Error(self, "Unknown input: " .. tostring(iname))
    end
end

function ENT:Think()
    if not WireLib or not self.WireState then return end
    -- Update wire outputs using the centralized system
    ActionRecorder.Wire.UpdateOutputs(self)
    self:NextThink(CurTime() + 0.1)
    return true
end

function ENT:ResetPlayback()
    --ARLog("ResetPlayback called via wire input")
    self:StopPlayback(true)
    -- Reset all animation info to frame 1
    for _, info in pairs(self.AnimationInfo or {}) do
        if info then
            info.currentFrameIndex = 1
            info.status = AR_ANIMATION_STATUS.FINISHED
        end
    end

    -- Update wire outputs immediately to reflect the reset
    if self.WireState then ActionRecorder.Wire.UpdateOutputs(self) end
end

function ENT:SetCurrentFrame(frame)
    --ARLog("SetCurrentFrame called with frame: " .. tostring(frame))
    -- Set all entities to the specified frame
    for _, info in pairs(self.AnimationInfo or {}) do
        if info and info.frameCount then info.currentFrameIndex = math.Clamp(frame, 1, info.frameCount) end
    end

    -- Apply the frame data immediately by processing a single frame
    self:ProcessPlayback()
    -- Update wire outputs immediately
    if self.WireState then ActionRecorder.Wire.UpdateOutputs(self) end
end