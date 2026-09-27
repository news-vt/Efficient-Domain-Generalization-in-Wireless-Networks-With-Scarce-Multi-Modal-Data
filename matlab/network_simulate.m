function network_simulate(gpsEpiPath, netEpiPath, txPos, bsArrayOrientation)
% function [] = network_simulate(saveroot, blenderpath, txPos, bsArrayOrientation)
    % Transpose the transmitter position and base station orientation for compatibility
    txPos = txPos.';
    bsArrayOrientation = bsArrayOrientation.';

    fc_ghz = 28;


    % Set the Python environment for Blender
    % pyenv('Version', blenderpath);


    
    % Define the root folder path for GPS and network data
    % folderPath = saveroot;
    % gpsPath = folderPath + "/_out_gps/";
    % contents = dir(gpsPath);
    % 
    % % Filter out only subfolders, excluding '.' and '..'
    % subFolders = contents([contents.isdir] & ~ismember({contents.name}, {'.', '..'})); %eposide folders

    % % Iterate through each subfolder
    % for epiIdx = 1:length(subFolders)
    %     gpsEpiPath = gpsPath + subFolders(epiIdx).name; % Path to GPS data for the current episode
    %     netEpiPath = folderPath + "/_out_net/" + subFolders(epiIdx).name; % Path to save network data
    % 

    % Create the network output folder if it doesnt exist
    if ~isfolder(netEpiPath)
        mkdir(netEpiPath);
    end
    disp(">> gpsEpiPath = " + gpsEpiPath);

    % Get the list of CSV files in the current GPS folder
    csvFiles = dir(fullfile(gpsEpiPath, '*.csv'));

    % Process each CSV file in the folder
    for k = 1:length(csvFiles)
        inputfilename = string(csvFiles(k).name);

        % Skip processing if the output file already exists
        if isfile(netEpiPath + "/" + inputfilename + ".mat")
            disp(inputfilename + " already exists.");
            continue
        end

        % Combine 3D map data using Blender


        % script_path = "/path/to/repo/matlab/bpy_combine.py";
        % datapath = saveroot;
        % filename = string(subFolders(epiIdx).name) + "/" + inputfilename;
        % modelname = "Town10_2lane.glb";
        % output_file = "temp_map.glb";

        %cmd = sprintf('"%s" --background --python "%s" -- "%s" "%s" "%s" "%s"', ...
        %    '/path/to/blender-4.2.0-linux-x64/blender-launcher', script_path, datapath, filename, modelname, output_file);
        %[status, cmdout ] = system(cmd);
        %disp(cmdout)



        % Perform ray tracing and network simulation
        [rays_result, ~, txArray, num_vehicle, bsArrayOrientation] = ...
            GetNetworkInfo(gpsEpiPath, inputfilename, "temp_map.ply", txPos, bsArrayOrientation);

        % Initialize variables for RSS (Received Signal Strength) calculation


        %Calculate RSS of each receiver
        % ---------- constants ---------------------------------------------------
        Pt_dBm = 43.98;                     % 25 W transmitter => 10*log10(25e3)
        
        numReceivers = numel(rays_result);
        rss_vals  = nan(numReceivers,1);    % dBm
        positions = nan(numReceivers,3);    % x y z  (metres)
        los_flag = false(numReceivers,1);      % 0 = all NLoS, 1 = at least one LoS
        rss_LOS_3gpp  = nan(numReceivers,1);

        for i = 1:numReceivers
            rays_i = rays_result{i};
            if isempty(rays_i),  continue, end

            % ---------- 1) keep at most five strongest rays ----------------------
            allPL = [rays_i.PathLoss];                % dB, lower = stronger
            [~,idx] = sort(allPL,'ascend');           % sort by strength
            idx     = idx(1 : min(5,numel(idx)));     % take ≤ 5
            selRays = rays_i(idx);

            % ----- non-coherent power sum ---------------------------------------
            Pr_W = 0;                       % accumulate linear Watts
            hasLOS = false;             % reset for this receiver

            for r = 1:numel(selRays)
                pl  = selRays(r).PathLoss;           % dB
                Pr_dBm = Pt_dBm - pl;               % link budget
                Pr_W   = Pr_W + 10^(Pr_dBm/10)/1e3; % convert to W, add
                if selRays(r).LineOfSight == 1 && selRays(r).NumInteractions == 0
                    hasLOS = true;
                end
            end

            rss_vals(i) = 10*log10(Pr_W*1e3);       % back to dBm
            los_flag(i) = hasLOS;                 % 1 or 0
            % store one copy of the receiver coordinates
            positions(i,:) = selRays(1).ReceiverLocation(:).';

            % ---------- 3) 3GPP UMi-LOS theoretical power ------------------------
            % distance Tx->Rx  (assumes txPos is [x,y,z] in *same* Cartesian frame)
            d_m = norm( positions(i,:) - txPos(:).' );
            % PL_LOS = 32.4 + 21*log10(d_m) + 20*log10(fc);  % freespace below 10 m
            PL_LOS = 32.4 + 21*log10(d_m) + 20*log10(fc_ghz);  % 38.901 UMi-LOS
            
            rss_LOS_3gpp(i) = Pt_dBm - PL_LOS;                     % dBm
        end
        
        % ---------- write CSV ---------------------------------------------------
        matFile = fullfile(netEpiPath, inputfilename + ".mat");          % rays_result
        csvFile = fullfile(netEpiPath, inputfilename + "_rss_map.csv");  % RSS tabl

        tbl = table( positions(:,1) , positions(:,2) , positions(:,3) , ...
                     rss_vals , los_flag ,rss_LOS_3gpp, ...
                     'VariableNames',{'x_m','y_m','z_m','RSS_dBm','hasLoS', 'RSS_LoS_dBm'});
        writetable(tbl,csvFile);
        save(matFile , 'rays_result');
        
        fprintf("Done and saved:\n  %s\n  %s\n", csvFile, matFile);


        % % Save the results to a .mat file
        % fprintf('Done and Save: %s\n', fullfile(netEpiPath + "/" + inputfilename + ".mat"));
        % save(fullfile(netEpiPath + "/" + inputfilename + ".mat"), 'rays_result');
    end
end
% end