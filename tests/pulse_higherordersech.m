function ok = test()

% Compare pulse() output pulse shapes with mathematical expressions

% HS8
Params.tp = 0.600;  % µs
Params.Type = 'sech/uniformQ';
Params.Frequency = [-100 100];  % MHz
Params.beta = 10.6;  % 1/µs
Params.n = 8;
Params.Amplitude = 20;
Params.TimeStep = 0.0005; % µs

t0 = 0:Params.TimeStep:Params.tp;

% Amplitude modulation: sech
ti = t0-Params.tp/2;
A = sech((Params.beta)*(2^(Params.n-1))*(ti/Params.tp).^Params.n);
A = A*Params.Amplitude;

% Frequency modulation
f = cumtrapz(ti,A.^2/trapz(ti,A.^2));
BW = Params.Frequency(2)-Params.Frequency(1);
f = BW*f-BW/2;

% Phase modulation
phi = cumtrapz(ti,f);
phi = phi+abs(min(phi));

% Pulse
IQ0 = A.*exp(2i*pi*phi);

[~,IQ,modulation] = pulse(Params);

ok(1) = areequal(IQ0,IQ,1e-11,'abs');
ok(2) = areequal(A,modulation.A,1e-12,'abs');
ok(3) = areequal(f,modulation.freq,1e-12,'abs');
ok(4) = areequal(2*pi*phi,modulation.phase,1e-12,'abs');
