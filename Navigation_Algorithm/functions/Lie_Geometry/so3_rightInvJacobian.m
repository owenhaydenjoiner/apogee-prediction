function [Jrinv_so3] = so3_rightInvJacobian(so3)
% Function to calculate the Left Inverse Jacobian Matrix of a SO(3) 
% Lie Algebra or Lie Group.
%
% Inputs:
% so3 = 3x1 Lie Algebra
%
% Outputs:
% Jlinv_so3 = 3x3 Left Inverse Jacobian Matrix of SO(3)
%
% Date Created: 12/11/2020
%
% Created by: Joe Gibbs
%
% References:
%
% A Tutorial on SE(3) transformation parameterizations and on-manifold
% optimization - Jose Luis Blanco Claraco [2020]
%
% A Code for Unscented Kalman Filtering on Manifolds (UKF-M) - Brossard,
% Barrau, Bonnabel [2020]
%
% Nonparametric Second-order Theory of Error Propagation on Motion
% Groups - Wang, Chrikijian [2008]
%
% https://math.stackexchange.com/questions/301533/jacobian-involving-so3-exponential-map-logr-expm


% Transform the input if required
if isrow(so3)
    so3 = so3';
end

if length(so3) == 3
    % Define Lie Algebra as Rotation Vector
    w = so3;
else
    errordlg('Input to so3_rightInvJacobian has incorrect dimensions.','Dimension Error');
    return
end

% Calculate angle of Rotation (theta)
theta = norm(w);

% Calulate Wedge Operation
wv = so3_wedge(w);

% Condition for theta~0, use a First Order Taylor Series Expansion
if abs(theta) < 1e-9
    Jrinv_so3 = eye(length(so3)) - wv/2;
else
    alpha = w / theta;
    Jrinv_so3 = 0.5*theta*cot(theta/2)*eye(length(so3)) + ...
        (1 - 0.5*theta*cot(theta/2))*(alpha*alpha') -...
        0.5*theta*so3_wedge(alpha);
end

end
    