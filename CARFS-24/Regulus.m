mass_dry = 10; %kg
mass_wet = 15; %kg

altitude_launch = 100;%m
angle_launchrail = 1;%m

motor_path = ("Motors/Cesaroni_4025L1355-P.eng");%.eng file containing the thrust curve for the motor
Cd_mon_path = ("Rockets/Regulus/Regulus CD power on.csv");%csv file containing the Cd curve whilst motor is burning
Cd_moff_path = ("Rockets/Regulus/Regulus CD power off.csv");%csv file containing the Cd curve whilst motor is not burning

Cd_airbrakes = ("");%csv file containing a look up table of Cd vs mach no. vs deployment angle
