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

local uid = {}

function uid.wakeup()
    -- quick exit if no apiVersion
    if ofs3.session.mcu_id == nil then  

            ofs3.session.mcu_id = "a3e5f2d7-9c4b-4e6a-b8f1-3d7e2c9a1f45"

    end

end

function uid.reset()
    ofs3.session.mcu_id = nil
end

function uid.isComplete()
    if ofs3.session.mcu_id ~= nil  then
        return true
    end
end

return uid