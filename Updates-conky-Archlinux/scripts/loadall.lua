-- conky-clock-lua V4
-- by @wim66
-- v4 6-April-2024

-- Set the path to the scripts folder
package.path = "./scripts/?.lua"
-- ###################################


require 'background'
require 'conky_checkupdates'

function conky_main()
     conky_draw_background()
     conky_draw_text()    
end

