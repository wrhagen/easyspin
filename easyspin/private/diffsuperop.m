% diffsuperop   Calculation of diffusion operator matrix for general potential
%
% This function computes the diffusion superoperator matrix:
% - It can use either LML or LMKjK basis, depending on what is given in basis.
% - It requires a diagonal diffusion tensor.
% - It does not require any particular order of spatial basis functions.
%
% Input:
%   basis     Structure with quantum numbers for orientational
%             basis. If .jK is given, the K-symmetrized (L,M,K,jK) basis is
%             used, otherwise the (L,M,K) basis is used. All field must have
%             the same number of elements.
%     .L      L quantum numbers
%     .M      M quantum numbers
%     .K      K quantum numbers
%     .jK     jK quantum numbers (optional) If given, use LMKjK basis,
%             if missing, use LMK basis.
%   R         array with 3 principal values of diffusion tensor (s^-1)
%   Potential (optional) structure 
%     .xlmk   expansion coefficients, as returned by chili_xlmk
%     .xlk    expansion coefficients, as returned by chili_xlk
%
% Output:
%   Gamma    diffusion superoperator in the given LMK or LMKjK basis (s^-1)

function Gamma = diffsuperop(basis,R,Potential)

usePotential = nargin==3 && isfield(Potential,'lambda') && any(Potential.lambda(:));

useKSymmetrizedBasis = isfield(basis,'jK') && ~isempty(basis.jK) && any(basis.jK);

L = basis.L;
M = basis.M;
K = basis.K;
nBasis = numel(L);

Mzero = all(Potential.M==0);

if useKSymmetrizedBasis
  jK = basis.jK;
end

switch numel(R)
  case 1
    % isotropic
    Rz = R;
    Rperp = R;
    Rd = 0;
  case 3
    % principal values
    Rz = R(3);
    Rd = (R(1)-R(2))/4;
    Rperp = (R(1)+R(2))/2;
  otherwise
    error('Three principal values of diffusion tensor required.');
end

% Treat the cases of isotropic and axial diffusion tensors in the absence of
% an ordering potential. In these cases, the diffusion operator matrix is
% diagonal in both the LMK and LMKjK basis.
if ~usePotential && Rd==0
  diagonal = Rperp*(L.*(L+1)-K.^2) + Rz*K.^2;
  Gamma = spdiags(diagonal,0,nBasis,nBasis);
  return
end

% Potential-independent part of diffusion operator
%-------------------------------------------------------------------------------
% This works for both the LMK basis and the K-symmetrized basis.
Np = @(L,K) sqrt((L*(L+1)-K*(K+1))*(L*(L+1)-(K+1)*(K+2)));
Nm = @(L,K) sqrt((L*(L+1)-K*(K-1))*(L*(L+1)-(K-1)*(K-2)));
idx = 0;
for b1 = 1:nBasis
  L1 = L(b1);
  M1 = M(b1);
  K1 = K(b1);
  if useKSymmetrizedBasis
    jK1 = jK(b1);
  end
  for b2 = b1:nBasis % run only over diagonal and upper triangular part (matrix is hermitian)
    L2 = L(b2);
    if L1~=L2, continue; end
    M2 = M(b2);
    if M1~=M2, continue; end
    if useKSymmetrizedBasis
      jK2 = jK(b2);
      if jK1~=jK2, continue; end
    end
    K2 = K(b2);
    if K1~=K2 && K1~=K2+2 && K1~=K2-2, continue; end
    
    % Calculate axial contribution
    if K1==K2
      val_ = Rperp*L2*(L2+1) + (Rz-Rperp)*K2^2;
    else
      val_ = 0;
    end
    
    % Calculate rhombic contribution
    % (We know it's nonzero, since we treated the Rd==0 case above)
    if useKSymmetrizedBasis
      val2_ = Np(L2,K2)*(K1==K2+2) + Nm(L2,K2)*((K1==K2-2)+jK1*(-1)^(L1+K1)*(-K1==K2-2));
      val_ = val_ + Rd * val2_ / sqrt((1+(K1==0))*(1+(K2==0)));
    else
      val_ = val_ + Rd * (Np(L2,K2)*(K1==K2+2) + Nm(L2,K2)*(K1==K2-2));
    end
    
    % Store non-zero value
    if val_==0, continue; end
    idx  = idx + 1;
    row(idx) = b1;
    col(idx) = b2;
    values(idx) = val_;
    if b1~=b2 % store value in lower triangular part
      idx  = idx + 1;
      row(idx) = b2;
      col(idx) = b1;
      values(idx) = conj(val_);
    end
    
  end
end
Gamma = sparse(row,col,values,nBasis,nBasis);


% Potential-dependent part of diffusion operator
%-------------------------------------------------------------------------------
if ~usePotential, return; end

if Mzero
  Lxmax = size(Potential.xlk,1)-1;
  X = @(L,M,K) Potential.xlk(L+1,K+L+1);
else
  Lxmax = numel(Potential.xlmk)-1;
  X = @(L,M,K) Potential.xlmk{L+1}(M+L+1,K+L+1);
end

idx = 0;
for b1 = 1:nBasis
  L1  = L(b1);
  M1  = M(b1);
  K1  = K(b1);
  if useKSymmetrizedBasis
    jK1 = jK(b1);
  end  
  for b2 = b1:nBasis   % run only over diagonal and upper triangular part, since matrix is hermitian
    L2  = L(b2);
    M2  = M(b2);
    if Mzero
      if M1~=M2, continue; end
    end
    K2  = K(b2);
    if useKSymmetrizedBasis
      jK2 = jK(b2);
    end
      
    if useKSymmetrizedBasis
      
      val_ = 0;
      for Lx = abs(L1-L2):min(Lxmax,L1+L2) % limit to terms that satisfy triangle condition
        
        if abs(M1-M2)>Lx, continue; end
        
        v = 0;
        
        % calculate first K-dependent term, +-(K1-K2)
        if abs(K1-K2)<=Lx
          X1_ = X(Lx,M1-M2,K1-K2) + X(Lx,M1-M2,-K1+K2)*jK1*jK2*(-1)^(Lx+K1+K2);
          if X1_~=0
            v = v + X1_*wigner3j(L1,Lx,L2,-K1,K1-K2,K2);
          end
        end
        
        % calculate second K-dependent term, +-(K1+K2)
        if abs(K1+K2)<=Lx
          X2_ = X(Lx,M1-M2,-K1-K2)*jK1*(-1)^(K1+Lx+L2) + X(Lx,M1-M2,K1+K2)*jK2*(-1)^(L2+K2);
          if X2_~=0
            v = v + X2_*wigner3j(L1,Lx,L2,-K1,K1+K2,-K2);
          end
        end        
        
        % combine terms, including M-dependent 3j-symbol
        if v==0, continue; end
        val_ = val_ + wigner3j(L1,Lx,L2,-M1,M1-M2,M2) * v;
        
      end
      
      if val_==0, continue; end
      
      prefactorjK = sqrt(jK1)'*sqrt(jK2)/2/sqrt((1+(K1==0))*(1+(K2==0)));
      prefactorL = sqrt((2*L1+1)*(2*L2+1));
      val_ = (-1)^(K1-M1) * prefactorL * prefactorjK * val_;
      
    else
      
      val_ = 0;
      for Lx = abs(L1-L2):min(Lxmax,L1+L2)
        if abs(M1-M2)>Lx, continue; end
        if abs(K1-K2)>Lx, continue; end
        
        X_ = X(Lx,M1-M2,K1-K2);
        if X_==0, continue; end
        
        % calculate M-dependent 3j-symbol
        jjjxM = wigner3j(L1,Lx,L2,-M1,M1-M2,M2);
        if jjjxM==0, continue; end
        
        % calculate K-dependent 3j-symbol
        jjjxK = wigner3j(L1,Lx,L2,-K1,K1-K2,K2);
        if jjjxK==0, continue; end
        
        % combine terms
        val_ = val_ + X_ * jjjxM * jjjxK;
      end
      val_ = (-1)^(K1-M1) * sqrt((2*L1+1)*(2*L2+1)) * val_;
      
    end
    
    % Store non-zero value
    if val_==0, continue; end
    idx = idx + 1;
    rowp(idx) = b1;
    colp(idx) = b2;
    valp(idx)  = val_;
    if b1~=b2
      idx = idx + 1;
      rowp(idx) = b2;
      colp(idx) = b1;
      valp(idx) = conj(val_);
    end
    
  end
end

Gamma = Gamma + sparse(rowp,colp,valp,nBasis,nBasis);

return
