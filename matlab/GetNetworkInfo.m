function [rays, tx, txArray, num_vehicle, bsArrayOrientation] = GetNetworkInfo(gpsEpiPath, inputfilename, mapname, txPos, bsArrayOrientation)
    % This function calculates network information using ray tracing.
    % Inputs:
    % - gpsEpiPath: Path to the GPS data directory
    % - inputfilename: Name of the input GPS data file
    % - mapname: Name of the 3D map file
    % - txPos: Position of the transmitter (base station)
    % - bsArrayOrientation: Orientation of the base station antenna
    % Outputs:
    % - rays: Ray tracing results
    % - tx: Transmitter site object
    % - txArray: Transmitter antenna array
    % - num_vehicle: Number of vehicles in the simulation
    % - bsArrayOrientation: Orientation of the base station antenna
    pe = pyenv;
    pythonExe = pe.Executable;  

    tic
    disp('bulding a map')
    [pathstr, basename, ext] = fileparts(mapname);


    % if strcmpi(ext,'.glb')
    %     plyName = fullfile(pathstr, basename + ".ply");
    % 
    %     if ~isfile(plyName)                % convert only the first time
    %         pe         = pyenv;            % your active Python
    %         pythonExe  = pe.Executable;
    % 
    %         % make sure trimesh is available
    %         system(sprintf('"%s" -m pip install --quiet --upgrade trimesh',pythonExe));
    % 
    %         % call a one-liner that loads GLB and writes PLY
    %         cmd = sprintf(['"%s" - <<PY\n' ...
    %                        'import sys, trimesh, pathlib\n'  ...
    %                        'm = trimesh.load("%s")\n'        ...
    %                        'm.export("%s")\n'                ...
    %                        'PY'], ...
    %                        pythonExe, mapname, plyName);
    % 
    %         status = system(cmd);
    %         if status~=0
    %             error("GLB→PLY conversion failed (exit %d)",status);
    %         end
    %     end
    % 
    %     mapname = plyName;                 % from here on we read the PLY
    % end





    % cleanName = fullfile(pathstr, basename + "_nocolor" + ext);
    
    % 3) assemble a call to that exact interpreter
    %cmd = sprintf(  ...
     %   '%s strip_colors.py "%s" "%s"', ...
      %   pythonExe, mapname, cleanName);
    
    %disp("Running: " + cmd)    % for sanity check
    %status = system(cmd);
    
    %if status~=0
    %   error("Python strip_colors failed (exit %d)", status);
    %end
    
    % now use the cleaned glb
    % mapname = char(cleanName);



    % 0)  PERSISTENT CACHE
    %     – facesStatic / vertsStatic : raw city mesh (loaded once)
    %     – viewerStatic              : hidden siteviewer (opened once)
    % ---------------------------------------------------------------
    persistent facesStatic vertsStatic viewerStatic mapCached
    
    % -------- load / create the static part only the first time -----
    if isempty(viewerStatic) || ~isvalid(viewerStatic) || ~strcmp(mapCached,mapname)
        fprintf('[Init] Reading static GLB ...\n');
        m            = readSurfaceMesh(mapname);              % slow only once
        facesStatic  = double(m.Faces);
        vertsStatic  = double(m.Vertices);
        mapCached    = mapname;

    end

    % Load GPS data from the input file
    gpsfilePath = fullfile(gpsEpiPath, inputfilename);
    data = readtable(gpsfilePath);
    %viewer = siteviewer(SceneModel=mapname, ShowEdges=false, ShowOrigin=false, Visible ='off');

    
    %% Transmitter (Tx) parameters
    fc = 28e9; % Carrier frequency (28 GHz)
    c = physconst('LightSpeed'); % Speed of light (m/s)
    lambda = c / fc; % Wavelength
    bsAntSize = [8 8]; % Base station antenna size (8x8 elements)
    
    %% Define the base station antenna array for beamforming
    txArray = phased.URA('Size', bsAntSize, 'ElementSpacing', 0.5*lambda*[1 1]);  
    tx = txsite("cartesian", Antenna=txArray, AntennaAngle=bsArrayOrientation, ...
        AntennaPosition=txPos, AntennaHeight=0.5,  TransmitterPower=25, TransmitterFrequency=fc);

    
    %% User Equipment (UE) antenna parameters
    ueAntSize = [2 2]; % UE antenna size (2x2 elements)   
    numrxantenna = 4;
    x_min = -10; x_max = 60; y_min = 44; y_max = 86.32;
    numXgrids = 10;  % For example, you want 10 points per axis
    numYgrids = 8;

    %% Define the propagation model for ray tracing
    pm = propagationModel("raytracing", ...
        CoordinateSystem="cartesian", ...
        AngularSeparation="High", ...
        MaxNumDiffractions=1, Method="sbr", ...
        MaxNumReflections=1, MaxAbsolutePathLoss=120);

    %% Linearly spaced points
    grid_x_vals = linspace(x_min, x_max, numXgrids);
    grid_y_vals = linspace(y_min, y_max, numYgrids);
    [grid_x, grid_y] = meshgrid(grid_x_vals, grid_y_vals);

    % [grid_x , grid_y] = meshgrid(x_min:gridres:x_max, y_min:gridres:y_max);
    numrx = numel(grid_x);
    rxArray = cell(1, numrx);
    rx = repmat(rxsite, 1, numrx);
    for k=1:numrx
        rxPos = [grid_x(k); grid_y(k); 1.5];
        %rxArray{k} = phased.URA('Size',ueAntSize,'ElementSpacing',0.5*lambda*[1 1]);
        rxArray{k} = phased.ULA('NumElements', numrxantenna, 'ElementSpacing',0.5*lambda);
        rx(k)      = rxsite("cartesian", Antenna=rxArray{k}, AntennaPosition=rxPos);
    end



    
    %% Vehicle HEIGHT table (top face above ground, metres)

    vehLength = 5;   % << same footprint for every cuboid >>
    vehWidth  = 1.8;
    vehHeight = 1.5;

    % heightkeys = { ...
    %     'vehicle.audi.a2', 'vehicle.audi.etron', 'vehicle.audi.tt', ...
    %     'vehicle.bmw.grandtourer', 'vehicle.carlamotors.carlacola', ...
    %     'vehicle.carlamotors.firetruck', 'vehicle.chevrolet.impala', ...
    %     'vehicle.citroen.c3', 'vehicle.dodge.charger_2020', ...
    %     'vehicle.dodge.charger_police', 'vehicle.ford.ambulance', ...
    %     'vehicle.ford.mustang', 'vehicle.lincoln.mkz_2017', ...
    %     'vehicle.lincoln.mkz_2020', 'vehicle.mercedes.coupe', ...
    %     'vehicle.mercedes.coupe_2020', 'vehicle.micro.microlino', ...
    %     'vehicle.mini.cooper_s', 'vehicle.mini.cooper_s_2021', ...
    %     'vehicle.mitsubishi.fusorosa', 'vehicle.nissan.micra', ...
    %     'vehicle.nissan.patrol', 'vehicle.nissan.patrol_2021', ...
    %     'vehicle.seat.leon', 'vehicle.tesla.cybertruck', ...
    %     'vehicle.toyota.prius', 'vehicle.volkswagen.t2', 'vehicle.carlamotors.european_hgv', ...
    %     'vehicle.mercedes.sprinter', 'vehicle.volkswagen.t2_2021', 'vehicle.volkswagen.t2'};

    keys = { ...
        'vehicle.volkswagen.t2_2021', 'vehicle.bmw.grandtourer', 'vehicle.nissan.patrol_2021', ...
        'vehicle.dodge.charger_2020', 'vehicle.dodge.charger_police', 'vehicle.mitsubishi.fusorosa', ...
        'vehicle.carlamotors.european_hgv','vehicle.carlamotors.firetruck', 'vehicle.tesla.model3', ...
        'vehicle.tesla.cybertruck','vehicle.volkswagen.t2','vehicle.carlamotors.carlacola', ...
        'vehicle.jeep.wrangler_rubicon','vehicle.toyota.prius','vehicle.nissan.patrol', ...
        'vehicle.mercedes.sprinter','vehicle.ford.ambulance' };
    % 
    % heightvalues = [ ...
    %     1.7, 1.8, 1.6, 2.5, 2.9, 4.5, 1.5, 1.7, 1.7, 1.7, ...
    %     2.6, 1.4, 1.7, 1.7, 1.8, 1.6, 1.5, 1.6, 1.8, 5.0, ...
    %     1.7, 2.4, 2.4, 1.6, 2.4, 1.6, 2.5, 3.0, 3.0, 3.0, ...
    %     3.0];

    heightvalues = [ ...
    2.3, 2.3, 2.0, 1.49, 1.49, 5.0, 4.5, 4.5, 1.49, 2.10, ...
    2.5, 2.5, 1.49, 1.49, 2.0, 2.8, 2.5 ];

    heightMap = containers.Map(keys, heightvalues);

    % Lengths
    lengthvalues = [ ...
        4.44, 4.61, 5.57, 5.01, 4.97, 10.27, 7.94, 8.47, 4.79, 6.27, ...
        4.48, 5.20, 3.87, 4.51, 4.60, 5.92, 6.37 ];
    lengthMap = containers.Map(keys, lengthvalues);
    
    % Widths
    widthvalues = [ ...
        1.77, 2.24, 2.15, 1.88, 2.04, 3.94, 2.89, 2.89, 2.16, 2.39, ...
        2.07, 2.63, 1.91, 2.01, 1.93, 1.99, 2.35 ];
    widthMap = containers.Map(keys, widthvalues);

    num_vehicle = height(data);

    % ------------------------- BUILD VEHICLE MESH --------------------------
    allV = [];  allF = [];  vOff = 0;

    % halfL = vehLength/2;         % 5 m footprint → ±2.5 m
    % halfW = vehWidth /2;         % 1.8 m footprint → ±0.9 m

    for k = 1:num_vehicle
        L = vehLength; W = vehWidth; zTop = vehHeight;
        id   = string(data.Vehicle_ID(k));
        if isKey(lengthMap, id), L = lengthMap(id); end
        if isKey(widthMap, id), W = widthMap(id); end
        if isKey(heightMap,id),  zTop = heightMap(id);  end
        
        halfL = L/2;
        halfW = W/2;

        % centre of this vehicle from the CSV -------------------------------
        xc = data.X(k);
        yc = data.Y(k);

        % eight vertices in *world coordinates* -----------------------------
        v = [ xc-halfL  yc-halfW  0 ;
            xc+halfL  yc-halfW  0 ;
            xc+halfL  yc+halfW  0 ;
            xc-halfL  yc+halfW  0 ;
            xc-halfL  yc-halfW  zTop ;
            xc+halfL  yc-halfW  zTop ;
            xc+halfL  yc+halfW  zTop ;
            xc-halfL  yc+halfW  zTop ];

        % faces → 12 triangles ----------------------------------------------
        quads = [1 2 3 4 ; 5 6 7 8 ; 1 2 6 5 ; 2 3 7 6 ; 3 4 8 7 ; 4 1 5 8];
        tri   = zeros(12,3);
        for q = 1:6
            a = quads(q,:) + vOff;
            tri(2*q-1,:) = a([1 2 3]);
            tri(2*q  ,:) = a([1 3 4]);
        end

        allV = [allV ; v];
        allF = [allF ; tri];
        vOff = vOff + 8;          % next vertex offset
    end

    vehMesh = triangulation(allF, allV);

    %% ----- merge original map + vehicle cuboids ---------------------------

    % 1) read the static map (glTF, GLB, STL …) -----------------------------
    % m = readSurfaceMesh(mapname);           % requires Lidar Toolbox (R2022b+)
    % facesMap = m.Faces;                     % n×3, already triangles
    % vertsMap = m.Vertices;                  % n×3
    % 
    % % 2) offset vehicle indices and concatenate -----------------------------
    % facesVeh = vehMesh.ConnectivityList + size(vertsMap,1);
    % vertsVeh = vehMesh.Points;
    % 
    % facesAll = [facesMap      ; facesVeh];
    % vertsAll = [vertsMap      ; vertsVeh];
    % 
    % facesAll = double(facesAll);
    % vertsAll = double(vertsAll);
    % 
    % sceneMesh = triangulation(facesAll , vertsAll);
    % 
    % % 3) open Site Viewer with the unified mesh -----------------------------
    % viewer = siteviewer( ...
    %            SceneModel = sceneMesh , ...
    %            ShowEdges  = false     , ...
    %            ShowOrigin = false     , ...
    %            Visible = 'off');

    % ---------------------------------------------------------------
    % 3)  MERGE STATIC + VEHICLES AND UPDATE THE VIEWER IN-PLACE
    % ---------------------------------------------------------------

    facesVeh = vehMesh.ConnectivityList + size(vertsStatic,1);
    vertsVeh = vehMesh.Points;
    sceneTri = triangulation([facesStatic;facesVeh], ...
                             [vertsStatic;vertsVeh]);
    
    if ~isempty(viewerStatic) && isvalid(viewerStatic)
        delete(viewerStatic);                 % close old window (fast)
    end
    viewerStatic = siteviewer(SceneModel=sceneTri, ...
                              ShowEdges=false, ShowOrigin=false, Visible='off');

    toc
    %show(tx , "Map" , viewer);   
    %% Perform ray tracing between the transmitter and receivers
    tic
    disp('Do ray tracing')
    % rays = raytrace(tx, rx, pm, Map = viewer,  Type="power");
    rays = raytrace(tx, rx, pm, Map = viewerStatic, Type="power");
    % RSS = sigstrength(rx, tx, pm, Map = viewer);
    % disp(RSS)
    toc
    

    
    % Close the site viewer
    %viewer.close
    end