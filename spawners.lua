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
    -- The side is the redstone output side on that remote
    -- computer. The text is exactly what appears on the
    -- Mob Control Panel.
    --
    -- DISABLING A SIDE:
    --   side = "N/A"
    --   side = false
    --   or simply remove the line.
    --
    -- Disabled/N/A sides are NOT sent to the Mob Control
    -- Panel and will not have a card on the screen.
    -- =====================================================

    configUpdateInterval = 300,
    statusUpdateInterval = 4,

    -- New/unlisted nodes show their Computer ID locally.
    -- All default sides are disabled, so a new node will not
    -- create junk N/A cards on the Mob Control Panel.
    default = {
        front = "N/A",
        back = "N/A",
        left = "N/A",
        right = "N/A"
    },

    computers = {
        [26] = {
            front = "N/A",
            back = "Wither Skeletons",
            left = "N/A",
            right = "N/A"
        },

        [20] = {
            front = "N/A",
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
