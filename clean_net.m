% — base paths (relative to the repository root) —
base_input_path  = "./base_station/_out_net";
base_output_path = "./base_station/_out_cleaned_net";

% make sure the cleaned‐output root exists
if ~exist(base_output_path,'dir')
    mkdir(base_output_path);
end

% find all episode folders (assumes they’re directories)
entries = dir(base_input_path);
is_episode = [entries.isdir] & ~ismember({entries.name}, {'.','..'});
episode_dirs = entries(is_episode);

for e = 1:numel(episode_dirs)
    ep_name   = episode_dirs(e).name;  % e.g. 'episode_301'
    in_dir    = fullfile(base_input_path,  ep_name);
    out_dir   = fullfile(base_output_path, ep_name);
    
    % create cleaned folder for this episode
    if ~exist(out_dir,'dir')
        mkdir(out_dir);
    end
    
    % list CSVs in this episode
    csv_files = dir(fullfile(in_dir, "*.csv"));
    
    for k = 1:numel(csv_files)
        % read
        fname   = csv_files(k).name;
        T       = readtable(fullfile(in_dir, fname));
        
        % ---------- ② repair rows that contain NaN ------------------------------
        locVars  = {'x_m','y_m','z_m'};                  % position columns
        rssVars  = {'RSS_dBm','RSS_LoS_dBm'};            % power columns
        nan_row  = any(ismissing(T{:, [locVars rssVars]}), 2);
        rowNum   = (1:height(T)).';                               % N×1 numeric
        nanIdxs   = find(nan_row);                               % Kx1 double


                % now loop K times, each time idx is scalar
        for j = 1:numel(nanIdxs)
            idx  = nanIdxs(j);          % scalar row index
        % for idx = find(nan_row').'      % each row that has at least one NaN
            % nearest valid row above & below -------------------------------
            prev = find(~nan_row & (rowNum < idx) , 1 , 'last');
            next = find(~nan_row & (rowNum > idx) , 1 , 'first');
            
            locVals  = [];  rssVals = [];  losFlags = [];
            if ~isempty(prev)
                locVals  = [locVals ; T{prev, locVars}];
                rssVals  = [rssVals ; T{prev, rssVars}];
                losFlags = [losFlags; T.hasLoS(prev)];
            end
            if ~isempty(next)
                locVals  = [locVals ; T{next, locVars}];
                rssVals  = [rssVals ; T{next, rssVars}];
                losFlags = [losFlags; T.hasLoS(next)];
            end
            
            % --------- fill the NaN row -------------------------------------
            if ~isempty(locVals)
                T{idx, locVars} = mean(locVals,1);           % always average positions
            end
            
            switch numel(unique(losFlags))
                case 0      % no neighbours (all rows NaN)  ─ fallback
                    T{idx, rssVars} = NaN;
                    T.hasLoS(idx)   = true;
                    
                case 1      % both neighbours have same LoS flag
                    T{idx, rssVars} = mean(rssVals,1);
                    T.hasLoS(idx)   = losFlags(1);
                    
                otherwise   % neighbours disagree: copy the LoS row
                    trueRow = rssVals(logical(losFlags), :);   % row where hasLoS = true
                    T{idx, rssVars} = trueRow;
                    T.hasLoS(idx)   = true;
            end
        end

        % find NLoS but RSS > RSS_LoS
        mask_noise = (T.RSS_dBm    > T.RSS_LoS_dBm) ...
                   & (T.hasLoS == false);
                   
        % override hasLoS
        T.hasLoS(mask_noise) = true;

        
        % write cleaned CSV
        [~, base, ~] = fileparts(fname);
        out_name     = base + "_cleaned.csv";
        writetable(T, fullfile(out_dir, out_name));
    end
end
