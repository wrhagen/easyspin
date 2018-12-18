function [err,data] = test(opt,olddata)

%===============================================================================
% Compare fast and general code with various potentials
%===============================================================================

Sys.g = [2.05 2.02 2.00];
Sys.logDiff = 7;

Exp.Field = 340;
Exp.mwRange = [9.4 9.9];
Exp.nPoints = 512;

Opt.LLMK = [10 6 6 6];

lam = +2;
LMK = [2 0 0; 2 0 2; 4 0 0; 4 0 2];

for p = 1:4
  Sys.Potential = [LMK(p,:) lam];
  
  Opt.LiouvMethod = 'fast';
  [B,y1] = chili(Sys,Exp,Opt);
  Opt.LiouvMethod = 'general';
  [B,y2] = chili(Sys,Exp,Opt);
  
  err(p) = ~areequal(y1,y2,1e-6*max(abs(y1)));
  
  if opt.Display
    subplot(4,1,p);
    plot(B,y1,B,y2);
    legend('fast','general');
    title(sprintf('lambda(%d,%d,%d) = %g',LMK(p,1),LMK(p,2),LMK(p,3),lam));
  end
  
end

err = any(err);
data = [];