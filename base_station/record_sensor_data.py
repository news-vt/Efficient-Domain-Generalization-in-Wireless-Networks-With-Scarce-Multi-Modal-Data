import carla
import argparse
import os
import time
import pandas as pd
import numpy as np 
# import config
from .config import GlobalConfig
import queue
import json

# # ─── CONFIG ────────────────────────────────────────────────────────────────────
# SAVE_ROOT = config.GlobalConfig.SAVE_ROOT           # no trailing slash
# EPISODE   = config.GlobalConfig.EPI_NAME
# MAP_X     = config.GlobalConfig.MAP_X                # your X bounds
# MAP_Y     = config.GlobalConfig.MAP_Y                 # your Y bounds (un‐inverted)
# FIXED_DELTA = config.GlobalConfig.FIXED_DELTA                       # seconds per sim step
# # ───────────────────────────────────────────────────────────────────────────────

# ─── CONFIG ────────────────────────────────────────────────────────────────────
SAVE_ROOT = GlobalConfig.SAVE_ROOT           # no trailing slash
EPISODE   = GlobalConfig.EPI_NAME
MAP_X     = GlobalConfig.MAP_X                # your X bounds
MAP_Y     = GlobalConfig.MAP_Y                 # your Y bounds (un‐inverted)
FIXED_DELTA = GlobalConfig.FIXED_DELTA                       # seconds per sim step
# ───────────────────────────────────────────────────────────────────────────────

def mkdir(path):
    os.makedirs(path, exist_ok=True)

def set_basestation(world):
    """
    Set the base station's position and orientation in the CARLA world.
    Args:
        world: The CARLA world object.
    """
    basestation = carla.Transform()
    basestation.location = carla.Location(*GlobalConfig.bs_location)
    basestation.rotation = carla.Rotation(*GlobalConfig.bs_rotation)
    world.get_spectator().set_transform(basestation)
    return

def delete_sensors(_client, _world):
    """
    Delete all sensor actors (camera, LiDAR, radar) in the CARLA world.
    Args:
        _client: The CARLA client object.
        _world: The CARLA world object.
    """
    actor_list = _world.get_actors()
    for actor in actor_list:
        if actor.type_id in ["sensor.camera.rgb", "sensor.lidar.ray_cast", "sensor.other.radar"]:
            _client.apply_batch([carla.command.DestroyActor(actor.id)])
    return



def main():
    """
    Main function to initialize the CARLA client, configure the world, and run sensors.
    """
    argparser = argparse.ArgumentParser(description=__doc__)
    argparser.add_argument('--host', metavar='H', default='127.0.0.1', help='IP of the host server (default: 127.0.0.1)')
    argparser.add_argument('-p', '--port', metavar='P', default=2000, type=int, help='TCP port to listen to (default: 2000)')
    argparser.add_argument('-m', '--matlab', metavar='M', default=False, type=bool, help='Generate sensing data and MATLAB network data simultaneously (but this may take a long time)')
    argparser.add_argument(
        '--tm-port',
        metavar='P',
        default=8000,
        type=int,
        help='Port to communicate with Traffic Manager (default: 8000)')
    
    args = argparser.parse_args()
    client = carla.Client(args.host, args.port)
    client.set_timeout(80.0)
    world = client.get_world()

    tm = client.get_trafficmanager(args.tm_port)
    tm.set_synchronous_mode(True)

    # tm.set_force_lane_change(False)
    # tm.set_keep_right_rule(True) 
    tm.set_global_distance_to_leading_vehicle(2.5) 

    settings = world.get_settings()
    settings.fixed_delta_seconds = FIXED_DELTA
    # settings.max_substep_delta_time = 0.025
    # settings.max_substeps           = 12   
    settings.synchronous_mode    = True
    world.apply_settings(settings)

    image_queue = queue.Queue()
    lidar_queue = queue.Queue()
    radar_queue = queue.Queue()


    set_basestation(world)  # Set the base station

    bp_lib       = world.get_blueprint_library()
    spawn_trans = world.get_spectator().get_transform()    


    # Configure camera blueprint
    camera_bp = bp_lib.filter("sensor.camera.rgb")[0]
    camera_bp.set_attribute("image_size_x", str(960))
    camera_bp.set_attribute("image_size_y", str(540))
    camera_bp.set_attribute('sensor_tick', f'{FIXED_DELTA}')
    camera_bp.set_attribute('fov', '90')

    # Configure LiDAR blueprint
    lidar_bp = bp_lib.filter("sensor.lidar.ray_cast")[0]
    lidar_bp.set_attribute('upper_fov', str(25.5))
    lidar_bp.set_attribute('lower_fov', str(-22.5))
    lidar_bp.set_attribute('channels', str(32))
    lidar_bp.set_attribute('range', str(250))
    lidar_bp.set_attribute('rotation_frequency', str(20))
    lidar_bp.set_attribute('points_per_second', str(1500000))
    lidar_bp.set_attribute('sensor_tick', f'{FIXED_DELTA}')

    # Configure radar blueprint
    radar_bp = bp_lib.filter("sensor.other.radar")[0]
    radar_bp.set_attribute('horizontal_fov', str(150.0))
    radar_bp.set_attribute('vertical_fov', str(30.0))
    radar_bp.set_attribute('range', str(50))
    radar_bp.set_attribute('sensor_tick', f'{FIXED_DELTA}')
    radar_bp.set_attribute('points_per_second', str(20000))

    # Create output directories if they don't exist
    # folderpath = config.GlobalConfig.SAVE_ROOT
    # epsode_name = config.GlobalConfig.EPI_NAME

    sensor_list = []

    camera = world.spawn_actor(blueprint=camera_bp, transform=spawn_trans)
    camera.listen(image_queue.put)
    sensor_list.append(camera)

    lidar = world.spawn_actor(blueprint=lidar_bp, transform=spawn_trans)
    lidar.listen(lidar_queue.put)
    sensor_list.append(lidar)

    # tf = lidar.get_transform()        # or spawn_trans
    # tf_dict = {
    #     "location": [tf.location.x, tf.location.y, tf.location.z],
    #     "rotation": [tf.rotation.roll, tf.rotation.pitch, tf.rotation.yaw]
    # }
    # with open(f"{SAVE_ROOT}/lidar_tf.json", "w") as f:
    #     json.dump(tf_dict, f, indent=2)

    radar_trans = spawn_trans
    radar_trans.location.z = 5
    radar_trans.rotation.pitch = 0
    radar = world.spawn_actor(blueprint=radar_bp, transform=radar_trans)
    radar.listen(radar_queue.put)
    sensor_list.append(radar)

    original_settings = world.get_settings()

    # counters and flags
    rgb_count   = 0
    lidar_count = 0
    radar_count = 0
    dirs_created = False



    # ── DRAIN ANY STALE MESSAGES ─────────────────────────────────────────────
    for q in (image_queue, lidar_queue, radar_queue):
        while not q.empty():
            q.get_nowait()
    # Now every queue is empty, so the very next get() is a fresh frame.
    started = False

    try:
        while True:
            frame = world.tick()
            # pull sensors
            try:
                img = image_queue.get(timeout=1.0)
                pc  = lidar_queue.get(timeout=1.0)
                rd  = radar_queue.get(timeout=1.0)
            except queue.Empty:
                continue

            vehicles = world.get_actors().filter('vehicle.*')  # Get all vehicles in the world
            captured_vehicles = [vehicle for vehicle in vehicles
                # Check if any vehicle is within the specified region
                if MAP_X[0] < vehicle.get_transform().location.x < MAP_X[1] and \
                MAP_Y[0] < -vehicle.get_transform().location.y < MAP_Y[1]]
        
            if not captured_vehicles:
                if started:
                    print("Vehicle left region -> ending capture loop")
                    break
                continue

            started = True

            # 4) prepare output directories
            if not dirs_created:
                for sub in ["_out_rgb", "_out_lidar", "_out_radar", "_out_gps"]:
                    mkdir(f"{SAVE_ROOT}/{sub}/{EPISODE}")
                dirs_created = True

            # now save image, lidar, radar, and CSV as before...
            img.save_to_disk(f"{SAVE_ROOT}/_out_rgb/{EPISODE}/{frame:06d}.png")

            rgb_count += 1

            pc.save_to_disk(f"{SAVE_ROOT}/_out_lidar/{EPISODE}/{frame:06d}.ply")

            lidar_count += 1

            points = np.frombuffer(rd.raw_data, dtype=np.dtype('f4'))  # Extract radar data
            points = np.reshape(points, (len(rd), 4))  # Reshape to (N, 4) format

            # arr = np.frombuffer(rd.raw_data, dtype=np.float32).reshape(-1,4)
            np.save(f"{SAVE_ROOT}/_out_radar/{EPISODE}/{frame:06d}.npy", points)

            radar_count += 1

            # ── write the csv data ──────────────────────────────────────
            vehicle_row = []
            for v in captured_vehicles:
                vehicle_row.append(
                {
                "Frame":       frame,
                "Timestamp":   time.time(),
                "Vehicle_ID":  v.type_id,
                "X":           v.get_transform().location.x,
                "Y":          -v.get_transform().location.y,
                "Z":           v.get_transform().location.z,
                "Yaw":         v.get_transform().rotation.yaw,
                "Pitch":       v.get_transform().rotation.pitch,
                "Roll":        v.get_transform().rotation.roll,
                })

            gps_file  = f"{SAVE_ROOT}_out_gps/{EPISODE}/{frame:06d}.csv"    
            pd.DataFrame(vehicle_row).to_csv(gps_file, mode='a', index=False)


            if (
               rgb_count   >= GlobalConfig.MAX_STEP or
               lidar_count >= GlobalConfig.MAX_STEP or
               radar_count >= GlobalConfig.MAX_STEP
            ):
                print("Reached max step for one of the sensors → ending episode")
                break


    finally:

        for sensor in sensor_list:
            if sensor.is_listening:
                sensor.stop()
        world.tick(80.0)     
        for sensor in sensor_list:
            sensor.destroy()
        client.apply_batch_sync([carla.command.DestroyActor(s.id)
                                 for s in sensor_list], do_tick=True)
        world.apply_settings(original_settings)

    return

if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        pass
    finally:
        print('\ndone.')