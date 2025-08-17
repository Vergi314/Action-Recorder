if CLIENT then
    hook.Add("OnSpecialKeyPress", "ActionRecorder_OnSpecialKeyPress", function(key)
        local pauseKey = GetConVar("actionrecorder_pausekey"):GetInt()
        if pauseKey == 0 then return end
        if key == pauseKey then
            net.Start("ActionRecorder_TogglePause_Targeted")
            net.SendToServer()
            return true -- Consume the key press
        end
    end)
end
