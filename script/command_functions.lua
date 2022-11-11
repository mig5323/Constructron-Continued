local ctron = require("__Constructron-Continued__.script.constructron")

local me = {}

me.reset_settings = function()
    settings.global["construct_jobs"] = {value = true}
    settings.global["rebuild_jobs"] = {value = true}
    settings.global["deconstruct_jobs"] = {value = true}
    settings.global["decon_ground_items"] = {value = true}
    settings.global["upgrade_jobs"] = {value = true}
    settings.global["repair_jobs"] = {value = false}
    settings.global["constructron-debug-enabled"] = {value = false}
    settings.global["allow_landfill"] = {value = true}
    settings.global["desired_robot_count"] = {value = 50}
    settings.global["desired_robot_name"] = {value = "construction-robot"}
    settings.global['max-worker-per-job'] = {value = 4}
    settings.global["max-jobtime-per-job"] = {value = 2}
    settings.global["entities_per_tick"] = {value = 100}
end

me.clear_queues = function()
    global.ghost_entities = {}
    global.deconstruction_entities = {}
    global.upgrade_entities = {}
    global.repair_entities = {}

    global.construct_queue = {}
    global.deconstruct_queue = {}
    global.upgrade_queue = {}
    global.repair_queue = {}

    for s, surface in pairs(game.surfaces) do
        global.constructrons_count[surface.index] = global.constructrons_count[surface.index] or 0
        global.stations_count[surface.index] = global.stations_count[surface.index] or 0
        global.construct_queue[surface.index] = global.construct_queue[surface.index] or {}
        global.deconstruct_queue[surface.index] = global.deconstruct_queue[surface.index] or {}
        global.upgrade_queue[surface.index] = global.upgrade_queue[surface.index] or {}
        global.repair_queue[surface.index] = global.repair_queue[surface.index] or {}
    end
end

me.reacquire_construction_jobs = function()
    for _, surface in pairs(game.surfaces) do
        local event = {}
        event["tick"] = game.tick
        local ghosts = surface.find_entities_filtered {
            name = {"entity-ghost", "tile-ghost"},
            force = {"player", "neutral"},
            surface = surface.name
        }
        game.print('found '.. #ghosts ..' entities on '.. surface.name ..' to construct.')
        for _, ghost in pairs(ghosts) do
            event["entity"] = ghost
            ctron.on_built_entity(event)
        end
    end
end

me.reacquire_deconstruction_jobs = function()
    for _, surface in pairs(game.surfaces) do
        local event = {}
        event["tick"] = game.tick
        local decons = surface.find_entities_filtered {
            to_be_deconstructed = true,
            force = {"player", "neutral"},
            surface = surface.name
        }
        game.print('found '.. #decons ..' entities on '.. surface.name ..' to deconstruct.')
        for _, decon in pairs(decons) do
            event["entity"] = decon
            ctron.on_entity_marked_for_deconstruction(event)
        end
    end
end

me.reacquire_upgrade_jobs = function()
    for _, surface in pairs(game.surfaces) do
        local event = {}
        event["tick"] = game.tick
        local upgrades = surface.find_entities_filtered {
            to_be_upgraded = true,
            force = "player",
            surface = surface.name
        }
        game.print('found '.. #upgrades ..' entities on '.. surface.name ..' to upgrade.')
        for _, upgrade in pairs(upgrades) do
            event["entity"] = upgrade
            event["target"] = "something"
            ctron.on_built_entity(event)
        end
    end
end

me.reload_entities = function()
    global.registered_entities = {}

    global.service_stations = {}
    global.constructrons = {}

    global.stations_count = {}
    global.constructrons_count = {}

    me.reacquire_stations()
    me.reacquire_ctrons()
end

me.reacquire_stations = function()
    for s, surface in pairs(game.surfaces) do
        global.stations_count[surface.index] = 0
        local stations = surface.find_entities_filtered {
            name = "service_station",
            force = "player",
            surface = surface.name
        }

        for k, station in pairs(stations) do
            local unit_number = station.unit_number
            if not global.service_stations[unit_number] then
                global.service_stations[unit_number] = station
            end

            local registration_number = script.register_on_entity_destroyed(station)
            global.registered_entities[registration_number] = {
                name = "service_station",
                surface = surface.index
            }

            global.stations_count[surface.index] = global.stations_count[surface.index] + 1
        end
        game.print('Registered ' .. global.stations_count[surface.index] .. ' stations on ' .. surface.name .. '.')
    end
end

me.reacquire_ctrons = function()
    for s, surface in pairs(game.surfaces) do
        global.constructrons_count[surface.index] = 0
        local constructrons = surface.find_entities_filtered {
            name = {"constructron", "constructron-rocket-powered"},
            force = "player",
            surface = surface.name
        }

        for k, constructron in pairs(constructrons) do
            local unit_number = constructron.unit_number
            if not global.constructrons[unit_number] then
                global.constructrons[unit_number] = constructron
            end

            local registration_number = script.register_on_entity_destroyed(constructron)
            global.registered_entities[registration_number] = {
                name = "constructron",
                surface = surface.index
            }

            global.constructrons_count[surface.index] = global.constructrons_count[surface.index] + 1
        end
        game.print('Registered ' .. global.constructrons_count[surface.index] .. ' constructrons on ' .. surface.name .. '.')
    end
end

me.reload_ctron_status = function()
    for k, constructron in pairs(global.constructrons) do
        ctron.set_constructron_status(constructron, 'busy', false)
        ctron.set_constructron_status(constructron, 'staged', false)
    end
end

me.reload_ctron_color = function()
    for k, constructron in pairs(global.constructrons) do
        ctron.paint_constructron(constructron, 'idle')
    end
end

me.recall_ctrons = function()
    for _, surface in pairs(game.surfaces) do
        if (global.stations_count[surface.index] > 0) and (global.constructrons_count[surface.index] > 0) then
            local constructrons = surface.find_entities_filtered {
                name = {"constructron", "constructron-rocket-powered"},
                force = "player",
                surface = surface.name
            }
            for _, constructron in pairs(constructrons) do
                local closest_station = ctron.get_closest_service_station(constructron)
                -- find path to station
                ctron.pathfinder.request_path({constructron}, "constructron_pathing_dummy" , closest_station.position)
            end
        else
            game.print('No stations to recall Constructrons to on ' .. surface.name .. '.')
        end
    end
end

me.clear_ctron_inventory = function()
    local slot = 1

    for c, constructron in pairs(global.constructrons) do
        local inventory = constructron.get_inventory(defines.inventory.spider_trunk)
        local filtered_items = {}

        for i = 1, #inventory do
            local item = inventory[i]

            if item.valid_for_read then
                if not filtered_items[item.name] then
                    constructron.set_vehicle_logistic_slot(slot, {
                        name = item.name,
                        min = 0,
                        max = 0
                    })
                    slot = slot + 1
                    filtered_items[item.name] = true
                end
            end
        end
    end
end

me.stats = function()
    local queues = {
        "registered_entities",
        "constructron_statuses",
        "ignored_entities",
        "allowed_items",
        "ghost_entities",
        "deconstruction_entities",
        "upgrade_entities",
        "repair_entities",
        "job_bundles",
        "constructrons",
        "service_stations",
    }
    local global_stats = {
    }
    for _, data_name in pairs(queues) do
        local data = global[data_name]
        if type(data)=="table" then
            global_stats[data_name] = table_size(data)
        else
            global_stats[data_name] = tostring(data)
        end
    end
    local surface_queues = {
        "constructrons_count",
        "stations_count",
        "construct_queue",
        "deconstruct_queue",
        "upgrade_queue",
        "repair_queue",
    }
    for s, surface in pairs(game.surfaces) do
        for _, data_name in pairs(surface_queues) do
            local data = global[data_name][surface.index]
            if type(data)=="table" then
                -- log(serpent.block(data))
                global_stats[surface.name .. ":" .. data_name] = table_size(data)
            else
                global_stats[surface.name .. ":" .. data_name] = tostring(data)
            end
        end
    end
    return global_stats
end

me.help_text = function()
    game.print('Constructron-Continued command help:')
    game.print('/ctron help - show this help message')
    game.print('/ctron (enable|disable) (debug|landfill|constructruction|deconstruction|ground_deconstruction|upgrade|repair) - toggle job types.')
    game.print('/ctron reset (settings|queues|entities|all)')
    game.print('/ctron clear all - clears all jobs, queued jobs and unprocessed entities')
    game.print('/ctron stats for a basic display of queue length')
    game.print('See Factorio mod portal for further assistance https://mods.factorio.com/mod/Constructron-Continued')
end

return me