class GlobalConfig:
    MAX_STEP = 5 # maximum step of each episode
    SAVE_ROOT = './base_station/'
    EPI_NAME = '/episode_1' #it will be changed automatically by record_episodes.py
    MAT_SAVE_ROOT = '../base_station/'
    BLENDER_PATH = '/path/to/blender-4.2.0-linux-x64/4.2/python/bin/python3.11' # Your Blender Path
    FIXED_DELTA  = 0.1


    # 2 Lane Scenario
    MAP_X = [-10-5, 60+5] #camera angle, so enlarge it by 5m 
    MAP_Y = [44, 86.32] #MAP_X and MAP_Y are matlab coordniates, so we multiply (-1) to the Y axis
    bs_location = [26.252628, -86.328842, 5] #This is Carla coordinates

    bs_rotation = [0, 90]
    
    ORIG_bs_location = bs_location.copy()
    ORIG_bs_rotation = bs_rotation.copy()
