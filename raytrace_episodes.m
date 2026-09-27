function raytrace_episodes(numEpisodes, prevEpisode)
% RAYTRACE_EPISODES  Run network_simulate for many episodes in a row.
%
%   raytrace_episodes(10)            % runs   0 … 10
%   raytrace_episodes(10, 5)         % runs   5 … 10
%
% Run from the repository root. Call non-interactively:
%   matlab -batch "raytrace_episodes(10, 1)"

if nargin < 2,  prevEpisode = 0;  end

projRoot = pwd;                         % remember where we started
addpath(fullfile(projRoot, 'base_station'));   % makes base_station/config.m visible
cfg = config();                         % load base config once

for idx = prevEpisode : numEpisodes
    fprintf('=== MATLAB pass • episode %d ===\n', idx);

    % ----------------------------------------------------------
    % episode-specific values
    % ----------------------------------------------------------
    cfg.EPI_NAME     = sprintf('episode_%d', idx);
 


    bs_location      = cfg.ORIG_bs_location;   bs_location(2) = -bs_location(2);  % flip Y
    bs_rotation      = cfg.ORIG_bs_rotation;   bs_rotation(1) = bs_rotation(1)+30; % +30° pitch

    % ----------------------------------------------------------
    % go to the folder where network_simulate() lives
    % ----------------------------------------------------------
    cd(fullfile(projRoot, 'matlab'));

    % ----------------------------------------------------------
    % run the heavy routine
    % ----------------------------------------------------------
    epiTag   = sprintf('episode_%d', idx);
    % gpsDir   = fullfile(cfg.SAVE_ROOT,'_out_gps', epiTag);
    % netDir   = fullfile(cfg.SAVE_ROOT,'_out_net', epiTag);

    % ---- absolute paths -------------------------------------------------
    gpsDir = fullfile(projRoot, cfg.SAVE_ROOT, '_out_gps', epiTag);
    netDir = fullfile(projRoot, cfg.SAVE_ROOT, '_out_net', epiTag);
    % ---------------------------------------------------------------------

    if ~isfolder(gpsDir)
        warning('Folder %s not found – skipped.', gpsDir);
        continue
    end

    network_simulate(gpsDir, netDir, bs_location, bs_rotation);
    % network_simulate(cfg.MAT_SAVE_ROOT, ...
    %                        cfg.BLENDER_PATH , ...
    %                        bs_location      , ...
    %                        bs_rotation      );

    % return to original folder so the next iteration starts clean
    cd(projRoot);
end

fprintf('✔ all episodes ray-traced\n');
end