--[[
 * Copyright (C) ofs3 Project
 *
 *
 * License GPLv3: https://www.gnu.org/licenses/gpl-3.0.en.html
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 3 as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 
 * Note.  Some icons have been sourced from https://www.flaticon.com/
 * 
]] --

local modelpreferences = {}

local modelpref_defaults ={
    dashboard = {
        theme_preflight = "nil",
        theme_inflight = "nil",
        theme_postflight = "nil",
    },
    general ={
        flightcount = 0,
        totalflighttime = 0,
        lastflighttime = 0,
    }
}

function modelpreferences.wakeup()

    -- quick exit if no apiVersion
    if ofs3.session.apiVersion == nil then return end    

    --- check if we have a mcu_id
    if not ofs3.session.mcu_id then
        return
    end
  

    if (ofs3.session.modelPreferences == nil)  then
             -- populate the model preferences variable

        if ofs3.config.preferences and ofs3.session.mcu_id then

            local modelpref_file = "SCRIPTS:/" .. ofs3.config.preferences .. "/models/" .. ofs3.session.mcu_id ..".ini"
            ofs3.utils.log("Preferences file: " .. modelpref_file, "info")

            os.mkdir("SCRIPTS:/" .. ofs3.config.preferences)
            os.mkdir("SCRIPTS:/" .. ofs3.config.preferences .. "/models")


            local slave_ini = modelpref_defaults
            local master_ini  = ofs3.ini.load_ini_file(modelpref_file) or {}


            local updated_ini = ofs3.ini.merge_ini_tables(master_ini, slave_ini)
            ofs3.session.modelPreferences = updated_ini
            ofs3.session.modelPreferencesFile = modelpref_file

            if not ofs3.ini.ini_tables_equal(master_ini, slave_ini) then
                ofs3.ini.save_ini_file(modelpref_file, updated_ini)
            end      
                   
        end
    end

end

function modelpreferences.reset()
    ofs3.session.modelPreferences = nil
end

function modelpreferences.isComplete()
    if ofs3.session.modelPreferences ~= nil  then
        return true
    end
end

return modelpreferences