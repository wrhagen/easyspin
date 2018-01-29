% spidyan    Simulate spindyanmics during pulse EPR experiments
%
%     [TimeAxis,Signal] = spidyan(Sys,Exp,Opt)
%     [TimeAxis,Signal,FinalState,StateTrajectories,Events] = spidyan(Sys,Exp,Opt)
%
%     Sys   ... spin system with electron spin and ESEEM nuclei
%     Exp   ... experimental parameters (time unit us)
%     Opt   ... simulation options
%
%     out:
%       TimeAxis          ... time axis
%       Signal            ... simulated signals of detected events
%       FinalState        ... density matrix/matrices at the end of the
%                             experiment
%       StateTrajectories ... cell array with density matrices from each
%                             timestep during evolution
%       Events            ... structure containing events

function varargout = spidyan(Sys,Exp,Opt) 

% [TimeAxis,Signal,Events,FinalState,StateTrajectories] = spidyan(Sys,Exp,Opt)
if (nargin==0), help(mfilename); return; end

% Input argument scanning, get display level and prompt
%=======================================================================
% Check Matlab version
VersionErrorStr = chkmlver;
error(VersionErrorStr);

% --------License ------------------------------------------------
LicErr = 'Could not determine license.';
Link = 'epr@eth'; eschecker; error(LicErr); clear Link LicErr
% --------License ------------------------------------------------

% Guard against wrong number of input or output arguments.
if (nargin<2) || (nargin>3), error('Wrong number of input arguments!'); end
if (nargout<0), error('Not enough output arguments.'); end
if (nargout>5), error('Too many output arguments.'); end

% Initialize options structure to zero if not given.
if (nargin<3), Opt = struct('unused',NaN); end
if isempty(Opt), Opt = struct('unused',NaN); end

if ~isstruct(Sys)
  error('First input argument (Sys) must be a structure!');
end
if ~isstruct(Exp)
  error('Second input argument (Exp) must be a structure!');
end
if ~isstruct(Opt)
  error('Third input argument (Opt) must be a structure!');
end
% 

% A global variable sets the level of log display. The global variable
% is used in logmsg(), which does the log display.
if ~isfield(Opt,'Verbosity'), Opt.Verbosity = 0; end
global EasySpinLogLevel
EasySpinLogLevel = Opt.Verbosity;


%----------------------------------------------------------------------
% Preprocess Input
%----------------------------------------------------------------------

% Check for magnetic field
if ~isfield(Exp,'Field')
  error('Exp.Field is required.')
elseif length(Exp.Field) == 1
  B = [0 0 Exp.Field];
else
  B = Exp.Field;
end

% Adapt Zeeman frequencies and g values for the selected simulation frame, 
% if they are provided
if isfield(Opt,'FrameShift') && ~isempty(Opt.FrameShift)
  if Opt.FrameShift < 0
    warning('The value provided for Opt.FrameShift is negative, but should be positive. The simulation frequency is always shifted to lower frequency and hence does not require a negative sign.')
    Opt.FrameShift = abs(Opt.FrameShift);
  end
  if isfield(Sys,'ZeemanFreq')
    Sys.ZeemanFreq =  Sys.ZeemanFreq - Opt.FrameShift;
  end
  
  if isfield(Sys,'g')  
    nElectrons = length(Sys.S);
    ng = size(Sys.g,1);
    
    %%%%% Transfer from GHz (Opt.FrameShift) to MHz (Opt.FrameShift*1000)
    gshift =  Opt.FrameShift*1000*1e9*planck/bmagn/Exp.Field(end);
    
    if ng == 1 || ng == 2 || (ng == 3 && nElectrons == 3)% isotropic, axial or rhombic g tensor
      Sys.g = Sys.g - gshift;
    elseif mod(ng,nElectrons) == 0 % full g tensor
      gshiftmat = diag([gshift gshift gshift]);
      gshiftmat = repmat(gshiftmat,[nElectrons,1]);
      Sys.g = Sys.g - gshiftmat;
    end
    
  end
end

  %%%%% Transfer from GHz to MHz
Exp.Frequency = Exp.Frequency*1000;

% Translate Frequency to g values
if isfield(Sys,'ZeemanFreq')
  %%%%% Transfer from GHz to MHz
  Sys.ZeemanFreq = Sys.ZeemanFreq*1000;
  if isfield(Sys,'g')
    [~, dgTensor] = size(Sys.g);
  else
    dgTensor = 1;
  end
  % Recalculates the g value 
  for ieSpin = 1 : length(Sys.ZeemanFreq)
    if Sys.ZeemanFreq(ieSpin) ~= 0
      g = Sys.ZeemanFreq(ieSpin)*1e9*planck/bmagn/Exp.Field(end);
      Sys.g(ieSpin,1:dgTensor) = g;
    end
  end
end

% Remove field ZeemanFreq if given, which is spidyan specific
if isfield(Sys,'ZeemanFreq')
  Sys = rmfield(Sys,'ZeemanFreq');
end

% Build the Event and Vary structure
[Events, Vary] = s_sequencer(Exp,Opt);


% Validate and build spin system as well as excitation operators
[Sys, Sigma, DetOps, Events, Relaxation] = s_propagationsetup(Sys,Events,Opt);

% Get Hamiltonian
Ham = sham(Sys,B);

%----------------------------------------------------------------------
% Propagation
%----------------------------------------------------------------------

% Calls the actual propagation engine
[TimeAxis, RawSignal, FinalState, StateTrajectories, Events] = s_thyme(Sigma, Ham, DetOps, Events, Relaxation, Vary);

%----------------------------------------------------------------------
% Signal Processing
%----------------------------------------------------------------------

% Signal postprocessing, such as down conversion and filtering and
% checking output of the timeaxis 
if ~isempty(RawSignal)
  
  if ~iscell(TimeAxis)
    if size(unique(TimeAxis,'rows'),1) == 1
      TimeAxis = TimeAxis(1,:);
    end
  else
    TimeAxisChanged = false;
    for iCell = 2 : length(TimeAxis)
      if ~isequal(TimeAxis{1},TimeAxis{iCell})
        TimeAxisChanged = true;
        break
      end
    end
    
    if ~TimeAxisChanged
      TimeAxis = TimeAxis{1};
    end
    
  end

  
  % Adapt FreqTranslation if needed
  if ~isfield(Opt,'FreqTranslation') || isempty(Opt.FreqTranslation)
    FreqTranslation = [];
    
  else
    nDetOps = numel(DetOps);
        
    if isfield(Opt,'FrameShift') && ~isempty(Opt.FrameShift)
      Opt.FreqTranslation(Opt.FreqTranslation > 0) = Opt.FreqTranslation(Opt.FreqTranslation > 0) - Opt.FrameShift;
      Opt.FreqTranslation(Opt.FreqTranslation < 0) = Opt.FreqTranslation(Opt.FreqTranslation < 0) + Opt.FrameShift;
    end
    FreqTranslation = zeros(1,nDetOps);
    FreqTranslation(1:length(Opt.FreqTranslation)) = Opt.FreqTranslation;
    
  end
  
  % Downconversion/processing of signal
  Signal = signalprocessing(TimeAxis,RawSignal,FreqTranslation);

else
  Signal = [];
end

if size(FinalState,1) == 1
  FinalState = squeeze(FinalState);
end

% Arranging Output
if nargout == 1
  varargout = {Signal};
elseif nargout == 2
  varargout = {TimeAxis,Signal};
elseif nargout == 3
  varargout = {TimeAxis,Signal,FinalState};
elseif nargout == 4
  varargout = {TimeAxis,Signal,FinalState,StateTrajectories};
elseif nargout == 5
  varargout = {TimeAxis,Signal,FinalState,StateTrajectories,Events};
end


