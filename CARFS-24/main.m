%% Computational Aerodynamic Rocket Flight AirBrake Simulation
% This code simulates the real-time actuation of airbrakes in rocket flight.
%
% Based on the Computational Aerodynamic Rocket Flight Simulation (CARFS) code by Michael Blaser
% Adapted to include airbrake actuation by: Jack Johnston
%
% Date: May 3, 2024
% Copyright © 2024 Jack Johnston. All rights reserved.


%% %%%********** Todo *********%%%
%Include CARFS for supersonic simulations

%Include 2d function for airbrakes Cd*A, mach no and deployment angle
% Add sensors, sampling KF ect.

%interpol

%% %%%*********MAINSCRIPT*********%%%
clc
clear all;

%% Simulation Settings
rocket_file_name = "Regulus";%File containing rocket data
dt = 0.01; %Simulation timestep
targetApogee = 3000;

apa = APA_single_particle();
P = [1, 0.1, 0.1; 0.1, 1, 0.1; 0.1 , 0.1 , 1];
controller = PIDController();


%% Import Data
%Rocket data
run(rocket_file_name);
fprintf(rocket_file_name + " data used for simulation")

%Airbrake data

%Airbrake1 = Airbrake(0, 90, cc_data); %Airbrake Cd*A, as function of Ma and deployment angle

%Motor data
file_path = fullfile(motor_path);
% Open the file
fileID = fopen(file_path, 'r');

% Check if file exists
if fileID == -1
    error(motor_path+' not found');
end

% Read the file
thrust_data = textscan(fileID, '%f %f', 'HeaderLines', 1);

% Close the file
fclose(fileID);

% Check if data is empty
if isempty(thrust_data{1}) || isempty(thrust_data{2})
    error('No data in ' + motor_file_name);
end

% Convert cell array to matrix
thrust_data = cell2mat(thrust_data);

%Functions for mass thrust
Rocket.burntime = max(thrust_data(:,1));
Rocket.thrust = @(t) (t >= 0 & t < 0.1) .* (t * (thrust_data(1,2) / 0.1)) + ...
                     (t >= 0.1 & t <= Rocket.burntime) .* interp1(thrust_data(:,1), thrust_data(:,2), t, 'linear', 'extrap');

Rocket.mass = @(t) max(mass_wet - (mass_wet - mass_dry) * min(t, Rocket.burntime) / Rocket.burntime, mass_dry);

%% Import drag coeff data for body(on and off)

% Drag Coefficient whilst motor is burning
% Read the CSV file
T = readtable(Cd_mon_path);

% Convert the table to a matrix
M = table2array(T);

% Extract Mach number and Cd data
mach_no = M(:, 1);
cd = M(:, 2);

% Find unique Mach numbers and get the corresponding indices
[mach_no_unique, idx] = unique(mach_no);

% Use the indices to get the corresponding unique Cd values
cd_unique = cd(idx);

% Create an interpolation function with the unique values
Rocket.dragcoef_on = @(x) interp1(mach_no_unique, cd_unique, x, 'linear', 'extrap');

% Drag Coefficient whilst motor is not burning
% Read the CSV file
T = readtable(Cd_moff_path);

% Convert the table to a matrix
M = table2array(T);

% Extract Mach number and Cd data
mach_no = M(:, 1);
cd = M(:, 2);

% Find unique Mach numbers and get the corresponding indices
[mach_no_unique, idx] = unique(mach_no);

% Use the indices to get the corresponding unique Cd values
cd_unique = cd(idx);

% Create an interpolation function with the unique values
Rocket.dragcoef_off = @(x) interp1(mach_no_unique, cd_unique, x, 'linear', 'extrap');

%%
% Set the desired apogee
setpoint = targetApogee;

% Set the process variable to launch altitude
process_variable = altitude_launch;
%% Define initial conditions
t = [0];
Rocket.x(1,1) = altitude_launch;
Rocket.x(1,2) = 0;
Rocket.x(1,3) = -9.81;

Rocket.state = "pad";
Rocket.Airbrake = Airbrake();

airbrake_velocity_log = [Rocket.Airbrake.velocity];
airbrake_position_log = [Rocket.Airbrake.P];
airbrake_angle_log = [Rocket.Airbrake.angle];
error_log = [0];
predicted_apogee = targetApogee;
t_last = 0;
Rocket.F_drag_airbrakes_out = [];
%% Main Loop
while Rocket.state ~= "descent"  && t(end) < 100
    t(end+1) = t(end) + dt;
    
    Rocket.state = state_update(Rocket);
    Rocket = dynamics_update(Rocket, t(end), dt);
    Rocket.Airbrake = Rocket.Airbrake.updateAirbrakes(dt);
    
    % Add controller, containing FP model and use that to update the
    % airbrake position

    %During coasting phase
    if Rocket.state == "burntout" && t(end) > 5 && t_last + 0.01 < t(end)
        t_last = t(end);
        % Predict the apogee using apa(current states, timestep)
        
        measurements = Rocket.x(end,:) + [0*randn(1), 0*randn(1) , 0*randn(1)]; %Generate noisy measurements based on the rocekts states
        [predicted_apogee, predicted_apogee_sigma, apa] = apa.getApogee(measurements, P, 0.1);
        
        % Calculate the controller output
        output = controller.calculate(setpoint, predicted_apogee);
        output = 0; % Turn off controller

        % Change airbrake position
        Rocket.Airbrake.desiredVelocity = output;
    end

    airbrake_velocity_log = [airbrake_velocity_log, Rocket.Airbrake.velocity];
    airbrake_position_log = [airbrake_position_log, Rocket.Airbrake.P];
    airbrake_angle_log = [airbrake_angle_log,Rocket.Airbrake.angle];
    error_log = [error_log, predicted_apogee - targetApogee];
end

%Comment out if dont want forced graphs
run("plot_data.m");

