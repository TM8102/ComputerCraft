return {
    -- =====================================================
    -- CENTRAL SPAWNER CONFIGURATION
    --
    -- SIMPLE FORMAT:
    --
    -- computers = {
    --     [COMPUTER_ID] = {
    --         front = "Spider",
    --         back  = "Zombie",
    --         left  = "N/A",
    --         right = "Skeleton"
    --     }
    -- }
    --
    -- N/A / NA / NONE / DISABLED / false / missing = disabled.
    -- Disabled sides are never sent to the Mob Control Panel.
    -- =====================================================

    -- These are SECONDS, because the remote node uses sleep().
    configUpdateInterval = 300,
    statusUpdateInterval = 4,

    default = {
        front = "N/A",
        back = "N/A",
        left = "N/A",
        right = "N/A"
    },

    computers = {
        [26] = {
            front = "Wilden Stalker",
            back = "Wither Skeletons",
            left = "Wilden Hunter",
            right = "Wilden Guardian"
        },

        [20] = {
            front = "Squid",
            back = "Spiders",
            left = "Ghasts",
            right = "Skeletons"
        },

        [24] = {
            front = "Zombie",
            back = "Charged Creepers",
            left = "Endermen",
            right = "N/A"
        }
    }
}
