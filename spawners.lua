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
    --         left  = "Creeper",
    --         right = "Skeleton"
    --     }
    -- }
    --
    -- The side is the redstone output side on that remote
    -- computer. The text is exactly what appears on the
    -- Mob Control Panel.
    --
    -- To disable a side, remove the line or set it to false.
    -- Keys are generated automatically as side_<side>.
    -- You do NOT need to edit the remote computers.
    -- =====================================================

    configUpdateInterval = 300,
    statusUpdateInterval = 4,

    -- Used by a new/unlisted remote computer so you can see
    -- its Computer ID before adding a real profile below.
    default = {
        front = "N/A",
        back = "N/A",
        left = "N/A",
        right = "N/A"
    },

    computers = {
        -- EXAMPLE:
        -- [123] = {
        --     front = "Spider",
        --     back = "Zombie",
        --     left = "Creeper",
        --     right = "Skeleton"
        -- },

        -- Add each remote spawner computer here.
        [26] = {
             front = "N/A",
             back = "Wither Skeletons",
             left = "N/A",
             right = "N/A"
         },
         [24] = {
             front = "Zombie",
             back = "Charged Creepers",
             left = "Endermen",
             right = "N/A"
         }
    }
}
