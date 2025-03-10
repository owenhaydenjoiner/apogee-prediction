classdef Navigation_Algorithm_Single
    %NAVIGATION_ALGORITHM Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
        estimator     % Struct of Kalman filters used for state estimation
                    % TranslationalKF - NED frame cartesian constant
                    % acceleration model
                    % AttitudeKF      - MEKF (Currently!)
        predictor   % Apogee prediction algorithm            
        Xkk         % Navigation State Group Element
        Zkk         % Navigation State Vector Element
        q           % Navigation Quaternion (body to NED)
        bg          % Gyroscope Biases
        ba          % Accelerometer Biases
        h_ap        % Estimate of apogee
        y           % Struct of latest measurements
        Pkk         % Error Covariance of estimator
        LLA0        % Initial Geodetic Coordinates
        wgs84       % Earth Model for NED to Geodetic Conversion
        settings
        state

        %% TEST STATES
        trueU
    end
    
    methods
        function obj = Navigation_Algorithm_Single(X0,Z0,P0,Qgyro,Qgyrob,Qacc,Qaccb,Rgnss,Ralt,Rmag,Ts,settingsKF,settingsApPred,LLA0)
            %NAVIGATION_ALGORITHM Construct an instance of this class
            %   Instantiate a Navigation_Algorithm class that consists of a
            %   linear NED 3D Kalman filter and a Quaternion attitude
            %   estimator
            obj.LLA0 = LLA0;
            obj.wgs84 = wgs84Ellipsoid;
            obj.state.burnout = false;

            obj.settings.useApogeePredict = settingsApPred.usePredict;
            obj.settings.useGNSSAltitude = settingsKF.useGNSSAltitude;

            % Declare RIEKF Kalman Filter
            obj.estimator = RIEKF(X0,Z0,P0,Qgyro,Qgyrob,Qacc,Qaccb,Rgnss,Ralt,Rmag,Ts);

            % Decalre Apogee Prediction Algorithm
            obj.predictor.apogeePredictor = Apogee_Predictor(settingsApPred.numParticles,Ts);
            obj.h_ap = 0;

        end
        
        function obj = updateNavigationStates(obj,buffer,qtruened)
            %UPDATENAVIGATIONSTATES Updates the filters
            %   Perform time updates and, if measurements are available,
            %   measurement updates of the Navigation Algorithms filters

            % Extract measurements from the buffer


            %% Time Update
            % We assume that the Navigation Algorithm runs at the frequency
            % of the IMU Accelerometer and Gyroscope measurements.

            % Translational Filter Prediction
            % obj.estimator = obj.estimator.propagate(buffer.y_omega,buffer.y_acc);
            
            obj.estimator.Xkk_1 = obj.estimator.Xk_1k_1;
            obj.estimator.Zkk_1 = obj.estimator.Zk_1k_1;
            obj.estimator.Pkk_1 = obj.estimator.Pk_1k_1;

            % obj.estimator.Xkk = obj.estimator.Xkk_1;
            % obj.estimator.Zkk = obj.estimator.Zkk_1;
            % obj.estimator.Pkk = obj.estimator.Pkk_1;
            
            %% Filter Measurement Update
            % GPS Correction Step
            if ~isnan(buffer.y_gnss)
                % Need to do PDF transformation to alter the statistics
                % Convert GNSS Measurement from Geodetic to NED
                [xn,yn,zn] = geodetic2ned(buffer.y_gnss(1),buffer.y_gnss(2),buffer.y_gnss(3),obj.LLA0(1),obj.LLA0(2),obj.LLA0(3),obj.wgs84);
                if obj.settings.useGNSSAltitude
                    y_gnss2 = [xn; yn; zn];
                else
                    y_gnss2 = [xn; yn];
                end
                % Translational Filter Correction
                obj.estimator = obj.estimator.updateGNSS(y_gnss2);

                % As filter has been updated, set the a prior state and
                % covariance equal to the updated state and covariance for
                % future updates. This is due to multiple update steps
                % being performed!
                obj.estimator.Xkk_1 = obj.estimator.Xkk;
                obj.estimator.Pkk_1 = obj.estimator.Pkk;
            end

            % Magmetometer Correction Step
            if ~isnan(buffer.y_mag)
                %Calculate Magnetic Field reference vector based on
                %current NED/Geodetic Position
                [LatEst,LongEst,Aest] = ned2geodetic(obj.estimator.Xkk(1,5),obj.estimator.Xkk(2,5),obj.estimator.Xkk(3,5),obj.LLA0(1),obj.LLA0(2),obj.LLA0(3),obj.wgs84);
                r_mag = wrldmagm(Aest,LatEst,LongEst,decyear(2024,7,4),'2020');

                %Attitude Filter Update using Magnetometer
                obj.estimator = obj.estimator.updateMag(buffer.y_mag,r_mag);

                %As filter has been updated, set the a prior state and
                %covariance equal to the updated state and covariance for
                %future updates. This is due to multiple update steps
                %being performed!
                obj.estimator.Xkk_1 = obj.estimator.Xkk;
                obj.estimator.Pkk_1 = obj.estimator.Pkk;
            end

            % Altimeter Correction Step
            % if ~isnan(buffer.y_alt)
            %     % Perform correction step with altimeter measurement
            %     obj.estimator = obj.estimator.updateAlt(buffer.y_alt);
            % end

            %% Update Nav States for use by other objects
            % Estimator states
            obj.Xkk = obj.estimator.Xkk;
            obj.Zkk = obj.estimator.Zkk;
            obj.Pkk = obj.estimator.Pkk;

            obj.q = rotm2quat(obj.estimator.Xkk(1:3,1:3))';
            obj.bg = obj.estimator.Zkk(1:3,1);
            obj.ba = obj.estimator.Zkk(4:6,1);


            %% Update Timestep
            obj.estimator.Xk_1k_1 = obj.estimator.Xkk;
            obj.estimator.Zk_1k_1 = obj.estimator.Zkk;
            obj.estimator.Pk_1k_1 = obj.estimator.Pkk;

            %% TO-DO - Calculate the updated rho, gravity at current altitude
            g = -9.80665;
            obj.predictor.apogeePredictor.g = g;
            % Pap = obj.estimator.Pkk(7:9,7:9);
            Pap = obj.estimator.Qa;

            %% TO-DO - State Machine
            % if obj.X(9) > 5
            %     obj.state.burnout = true;
            % end

            %% Perform Apogee Prediction based on current state estimates after burnout
            if obj.settings.useApogeePredict && obj.state.burnout
                % obj.predictor.apogeePredictor = obj.predictor.apogeePredictor.predict(-obj.x(7),-obj.x(8),-obj.x(9),Pap);
                obj.predictor.apogeePredictor = obj.predictor.apogeePredictor.predict(obj.trueU(1),obj.trueU(2),obj.trueU(3),Pap);
                obj.h_ap = obj.predictor.apogeePredictor.apogeePred;
            end
        end
    end
end

