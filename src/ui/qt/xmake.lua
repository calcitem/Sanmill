add_rules("mode.debug", "mode.release")

-- Set c code standard: c99, c++ code standard: c++17
set_languages("c99", "cxx17")

target("mill-pro")
    add_rules("qt.widgetapp")
    
    -- Include Directories
    add_includedirs(".", 
                    "../../../include", 
                    "../../", 
                    "../../test", 
                    "../../perfect", 
                    "translations")

    -- Source File Groups
    local qt_src_dir = "$(projectdir)" -- src/ui/qt/
    -- Absolute paths to avoid "__\\__" segments in object file directories (fixes LNK1181)
    local project_root_src_dir  = path.absolute("../../")          -- src/
    local perfect_src_dir       = path.absolute("../../perfect")   -- src/perfect/
    local test_src_dir          = path.absolute("../../test")      -- src/test/
    local translations_src_dir  = path.join(qt_src_dir, "translations") -- src/ui/qt/translations/

    -- Core source files from src/ (use absolute paths to ensure xmake generates valid object paths)
    local core_src_files = {
        "bitboard.cpp",
        "engine_commands.cpp",
        "engine_controller.cpp",
        "evaluate.cpp",
        "endgame.cpp",
        "main.cpp",
        "mcts.cpp",
        "mills.cpp",
        "misc.cpp",
        "movegen.cpp",
        "movepick.cpp",
        "opening_book.cpp",
        "option.cpp",
        "position.cpp",
        "rule.cpp",
        "search.cpp",
        "search_engine.cpp",
        "thread_pool.cpp",
        "uci.cpp",
        "ucioption.cpp",
        "self_play.cpp",
        "tt.cpp"
    }
    for _, f in ipairs(core_src_files) do
        add_files(path.join(project_root_src_dir, f))
    end

    -- Qt specific source files from src/ui/qt/
    add_files(qt_src_dir .. "/*.cpp")

    -- Perfect directory source files src/perfect/
    add_files(path.join(perfect_src_dir, "*.cpp"))

    -- Test utilities (e.g., AiSharedMemoryDialog)
    add_files(path.join(test_src_dir, "*.cpp"))

    -- Translation system source files src/ui/qt/translations/
    add_files(path.join(translations_src_dir, "*.cpp"))

    -- Qt MOC processing for headers
    local moc_headers = {
        path.join(qt_src_dir, "game.h"),
        path.join(qt_src_dir, "gamewindow.h"),
        path.join(qt_src_dir, "gameview.h"),
        path.join(qt_src_dir, "gamescene.h"),
        path.join(qt_src_dir, "database.h"),
        path.join(qt_src_dir, "client.h"),
        path.join(qt_src_dir, "movelistview.h"),
        path.join(qt_src_dir, "pieceitem.h"),
        path.join(qt_src_dir, "server.h"),
        path.join(test_src_dir, "ai_shared_memory_dialog.h"),
        path.join(project_root_src_dir, "thread.h"), -- Absolute path
        path.join(project_root_src_dir, "search_engine.h"), -- Absolute path
        path.join(translations_src_dir, "languagemanager.h")
    }
    add_files(moc_headers)
    
    -- Qt UI and Resource files
    add_files(path.join(qt_src_dir, "*.ui"))
    add_files(path.join(qt_src_dir, "*.qrc"))

    -- Add Qt frameworks
    add_frameworks("QtCore", "QtWidgets", "QtGui", "QtMultimedia")
    
    -- Add translation files (for reference, actual compilation handled by build scripts)
    add_extrafiles(path.join(translations_src_dir, "*.ts"))
    
    -- After build, copy translation files to output directory
    after_build(function (target)
        local targetdir = target:targetdir()
        local translations_output_dir = path.join(targetdir, "translations")
        
        if not os.isdir(translations_output_dir) then 
            os.mkdir(translations_output_dir)
        end
        
        local qm_files_source_dir = translations_src_dir
        for _, qm_file_name in ipairs(os.files(path.join(qm_files_source_dir, "mill-pro_*.qm"))) do
            local src_qm_path = path.join(qm_files_source_dir, qm_file_name)
            local dest_qm_path = path.join(translations_output_dir, qm_file_name)
            if os.isfile(src_qm_path) then
                os.cp(src_qm_path, dest_qm_path)
                print("Copied translation file: " .. src_qm_path .. " to " .. dest_qm_path)
            end
        end
    end)