% Base folder paths
repoRoot = fileparts(fileparts(mfilename('fullpath')));   % repository root
base_input_path = fullfile(repoRoot, "base_station", "_out_net");
base_output_path = fullfile(repoRoot, "base_station", "_out_heatmap");
txPos = [26.25, 86.3288];

episode_idx = '7';  % Change this index as needed
episode_name = "episode_" + episode_idx;
input_dir = fullfile(base_input_path, episode_name);
output_dir = fullfile(base_output_path, episode_name);

% Create output directory if it doesn't exist
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

% List all .mat files in the episode folder
%mat_files = dir(fullfile(input_dir, '*.mat'));
csv_files = dir(fullfile(input_dir, '*.csv'));

% for k = 1:length(mat_files)
%     file_name = mat_files(k).name;
%     input_path = fullfile(input_dir, file_name);
for k = 1:length(csv_files)
    file_name = csv_files(k).name;
    input_path = fullfile(input_dir, file_name);
    % % Load rays_result
    % data = load(input_path);
    % if ~isfield(data, "rays_result")
    %     continue;
    % end

    % Load rays_result

    data = readtable(input_path);

    % Extract x, y, and RSS (assumes columns are named exactly like this)
    x = data.x_m;
    y = data.y_m;
    v = data.RSS_dBm;
    rss_los = data.RSS_LoS_dBm;

    % Remove NaN values
    valid_idx = ~isnan(x) & ~isnan(y) & ~isnan(v);
    x = x(valid_idx);
    y = y(valid_idx);
    v = v(valid_idx);
    rss_los = rss_los(valid_idx);

    % Create grid
    grid_res = 1;  % Adjust resolution if needed
    xq = min(x):grid_res:max(x);
    yq = min(y):grid_res:max(y);
    [Xq, Yq] = meshgrid(xq, yq);

    Vq = griddata(x, y, v, Xq, Yq, 'natural');
    rss_los_q = griddata(x, y, rss_los, Xq, Yq, 'natural');


  
    
    % Plot interpolated heatmap
    fig = figure('Visible', 'off');
    imagesc(xq, yq, Vq);
    set(gca, 'YDir', 'normal');  % Fix y-axis direction
    colormap(jet);
    colorbar;
    title('Received Power (dBm)');
    xlabel('X'); ylabel('Y');
    axis equal tight;

    hold on;
    plot(txPos(1), txPos(2), 'wo', 'MarkerFaceColor', 'k', 'MarkerSize', 8);  % white edge, black dot
    
    if ismember('hasLoS', data.Properties.VariableNames)
        los_labels = data.hasLoS;
        nlos_idx = (los_labels == 0);
        plot(x(nlos_idx), y(nlos_idx), 'rx', 'MarkerSize', 8, 'LineWidth', 2);  % Red crosses
    end

    
    hold off;

    % Save figure
    [~, base_name, ~] = fileparts(file_name);
    save_path = fullfile(output_dir, base_name + "_heatmap.png");
    saveas(fig, save_path);
    close(fig);


       % Plot interpolated rss_los heatmap
    fig_los = figure('Visible', 'off');
    imagesc(xq, yq, rss_los_q);
    set(gca, 'YDir', 'normal');  % Fix y-axis direction
    colormap(jet);
    colorbar;
    title('Received Power_LoS (dBm)');
    xlabel('X'); ylabel('Y');
    axis equal tight;

    hold on;
    plot(txPos(1), txPos(2), 'wo', 'MarkerFaceColor', 'k', 'MarkerSize', 8);  % white edge, black dot
    
    % if ismember('hasLoS', data.Properties.VariableNames)
    %     los_labels = data.hasLoS;
    %     nlos_idx = (los_labels == 0);
    %     plot(x(nlos_idx), y(nlos_idx), 'rx', 'MarkerSize', 8, 'LineWidth', 2);  % Red crosses
    % end

    
    hold off;

    % Save figure
    [~, base_name, ~] = fileparts(file_name);
    save_path = fullfile(output_dir, base_name + "_heatmap_los.png");
    saveas(fig_los, save_path);
    close(fig_los);
end