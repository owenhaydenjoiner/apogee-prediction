clear all
data = readtable('data/simulated/Regulus/Regulus 100.0Hz.csv');
motor_path = ("data/simulated/Regulus/Cesaroni_4025L1355-P.eng");
rocket_path = ("data/simulated/Regulus/Rocket.txt");

timestamp = data.Time;
alt = data.Z;
vel = data.VZ;
acc = data.Az;

%% Add noise to data
alt = awgn(alt,40,'measured');
acc = awgn(acc,40,'measured');

alt_std_dev = std(data.Z - alt)
acc_std_dev = std(data.Az - acc)


%% Set up KF
x = [alt(1); 0; 0]; % [altitude; velocity; acceleration]

% Estimation error covariance
P = eye(3);

% System dynamics
H = [1 0 0; 0 0 1]; % Observation model

Q = [1 0 0 ; 
     0 1 0; 
     0 0 1]; % Static rocess noise covariance %0.001 * eye(3) 

R = diag([alt_std_dev^2, acc_std_dev^2]); % Measurement noise covariance


x_est = [];
x_est(:, 1) = x;
B = [0 0 1]';
u = 0;
uout = [];


%% Set up statemachine

launch_detected = false;
motor_burntout = false;
apogee_detected = false;
landed = false;


launch_time = 0;
burnout_time = 0;
apogee_time = 0;
apogee_altitude = 0;

predicted_apogee_time = 0;
predicted_apogee_altitude = 0;
predicted_apogee_times = [0];
predicted_apogee_altitudes = [0];


lower_bound = 0;
upper_bound = 0;
lower_bounds = [0];
upper_bounds = [0];

prediction_times = [0];


k = 1;
t = 0;
times = [t];
dt = 0.01;


%% Loop

while ~landed && ~apogee_detected && k < length(timestamp)
    t = t + dt;
    times  = [times, t];
    

    Q = [(dt^5)/20, (dt^4)/8, (dt^3)/6; (dt^4)/8, (dt^3)/3, (dt^2)/2; (dt^3)/6, (dt^2)/2, dt];%Dynamic process noise covariance
    A = [1 dt 0.5*dt^2; 
        0 1 dt; 
        0 0 1]; % State transition
    
    B = [0 0 dt]';
    %Control Input u ~ only thrust curve for these sims
        %Can't just add the thrust needs to be converted to a force
        %If keep adding force it spirals out of control, force as faction
        %of timestep sorts this.

    if  launch_detected && ~motor_burntout
        thrust = get_thrust(t - launch_time, motor_path);
        mass = get_mass(t - launch_time, rocket_path);
        u = (thrust/mass) - u;    
    end

    if motor_burntout
        u = 0;
    end
    uout = [uout, u];

    % Predict state and estimation error covariance
    x = A*x + B*u;
    P = A*P*A' + Q;

    % Compute Kalman gain
    K = P*H' / (H*P*H' + R);

    %Only update measurement step if new data
    if t >= timestamp(k)
        z = [alt(k); acc(k)]; % Measurement vector
        x = x + K * (z - H*x);
        P = (eye(3) - K*H) * P;
        k = k + 1;
    end
 
    % record the states
    x_est(:, end + 1) = x;



    %% Update state machine
    % Check for launch 
    if ~launch_detected && x_est(3, end) > 10 % Assuming launch when velocity > 10
        launch_detected = true;
        launch_time = t;
        disp("Launched at t=" + launch_time);
    end
    
    % Check motor burnout
    if launch_detected && ~motor_burntout && x_est(3, end) < 0 % Assuming motor burnout when acceleration < 0
        motor_burntout = true;
        burnout_time = t;
        disp("Burnout at t=" + burnout_time);
    end

    % Predict apogee after 0.1 second after motor burn-out and before apogee is detected
    if motor_burntout && t >  0.5 + burnout_time && ~apogee_detected
    
        [lower_bound, predicted_apogee_altitude, upper_bound] =  FP_Model(x, P, t, dt);
        predicted_apogee_altitudes = [predicted_apogee_altitudes, predicted_apogee_altitude];
        lower_bounds = [lower_bounds, lower_bound];
        upper_bounds = [upper_bounds, upper_bound];

        prediction_times = [prediction_times, t];
    end

    % Check apogee
    if motor_burntout && ~apogee_detected && x_est(2, end) < 0
        apogee_detected = true;
        apogee_time = t;
        apogee_altitude = x_est(1, end);
        disp("Apogee at t=" + apogee_time);
    end

    % Check landed
    if apogee_detected && ~landed && t >  1 + apogee_time && abs(x_est(2, end)) < 1 && abs(x_est(3, end)) < 1
        landed = true;
        landed_time = t;
        landed_altitude = x_est(1, end);
        disp("landed");
    end




end


% Check if the first figure exists, if not, create it
fig1 = findobj('Name', 'Figure 1');
if isempty(fig1)
    fig1 = figure('Name', 'Figure 1');
else
    figure(fig1); % Bring existing figure to front
end

% Clear figure 1
clf(fig1);

% Create tiled layout in figure 1
tiledlayout(fig1, 1, 1);

% Altitude estimates and measured data
nexttile;
plot(timestamp(1:k), alt(1:k), 'y');
hold on;
plot(times(1:k), x_est(1, 1:k), 'b');

% Plot lower, mean, and upper of apogee predictions
scatter(prediction_times, lower_bounds, 2, 'r'); 
scatter(prediction_times, predicted_apogee_altitudes, 3, 'g'); 
scatter(prediction_times, upper_bounds, 2, 'b'); 

title('Altitude Estimates and Measured Data');
xlabel('Time (s)');
ylabel('Altitude (m)');
legend('Measured Altitude', 'Estimated Altitude', 'Propagated Altitude');
xline(launch_time, 'g:', 'DisplayName', 'Launch Time');
xline(burnout_time, 'r:', 'DisplayName', 'Motor Burnout Time');
xline(apogee_time, 'g', 'DisplayName', 'Actual Apogee Time');
yline(apogee_altitude, 'g', 'DisplayName', 'Actual Apogee Altitude');
hold off;

% Check if the second figure exists, if not, create it
fig2 = findobj('Name', 'Figure 2');
if isempty(fig2)
    fig2 = figure('Name', 'Figure 2');
else
    figure(fig2); % Bring existing figure to front
end

% Clear figure 2
clf(fig2);

% Create tiled layout in figure 2
tiledlayout(fig2, 3, 2);

% Altitude estimates and measured data
nexttile;
plot(timestamp(1:k), data.Z(1:k), 'y');
hold on;
plot(times(1:k), x_est(1, 1:k), 'b');

title('Altitude Estimates and True Altitude');
xlabel('Time (s)');
ylabel('Altitude (m)');
legend('Measured Altitude', 'Estimated Altitude');
hold off;

% Altitude residuals
nexttile;
plot(timestamp(1:k), (data.Z(1:k) - x_est(1, 1:k)'), 'r');

title('Altitude Residuals');
xlabel('Time (s)');
ylabel('Altitude (m)');
legend('True - estimate');

% Velocity estimates and measured data
nexttile;
plot(timestamp(1:k), vel(1:k), 'y');
hold on;
plot(times(1:k), x_est(2, 1:k), 'b');

title('Velocity Estimates and True Velocity');
xlabel('Time (s)');
ylabel('Velocity (m/s)');
legend('Measured Velocity', 'Estimated Velocity');
hold off;

% Velocity residuals
nexttile;
plot(times(1:k), (data.VZ(1:k) - x_est(2, 1:k)'), 'r'); % Change plot type to scatter

title('Velocity Residuals');
xlabel('Time (s)');
ylabel('Velocity (m/s)');
legend('True - estimate');

% Acceleration estimates and measured data
nexttile;
plot(timestamp(1:k), data.Az(1:k), 'y');
hold on;
plot(times(1:k), x_est(3, 1:k), 'b');

title('Acceleration Estimates and True Acceleration');
xlabel('Time (s)');
ylabel('Acceleration (m/s^2)');
legend('Measured Acceleration', 'Estimated Acceleration');
hold off;

% Acceleration residuals
nexttile;
plot(times(1:k), (data.Az(1:k) - x_est(3, 1:k)'), 'r'); % Change plot type to scatter

title('Acceleration Residuals');
xlabel('Time (s)');
ylabel('Acceleration (m/s^2)');
legend('True - estimate');


