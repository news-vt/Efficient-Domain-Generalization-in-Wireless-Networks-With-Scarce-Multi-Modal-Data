function G = config()
% CONFIG  Return a persistent struct with global settings.
persistent C
if isempty(C)
    % ------------ paths ------------
    C.SAVE_ROOT      = './base_station/';
    C.MAT_SAVE_ROOT  = '../base_station/';
    C.BLENDER_PATH   = '/path/to/blender-4.2.0-linux-x64/4.2/python/bin/python3.11';

    % ------------ radio setup ------------
    C.ORIG_bs_location = [ 26.252628 , -86.328842 , 5   ];   % [x y z]  (python copy)
    C.ORIG_bs_rotation = [  0        ,  90        ];         % [pitch yaw]

    % ------------ misc ------------
    C.MAX_STEP = 5;
    C.MAP_X    = [-10 60];
    C.MAP_Y    = [44 86.32];
    C.EPI_NAME = '/episode_0';        % will be overwritten in the loop
    C.rx_height = 1.8;
end
G = C;
end