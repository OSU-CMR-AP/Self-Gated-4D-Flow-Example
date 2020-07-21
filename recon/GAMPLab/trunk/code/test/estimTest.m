% estimTest:  Main test program for the sum-product G-AMP algorithm
%-------------------------------------------------=----------------

% Tests the estimation of a sparse random vector x from an observation
% vector y generated by the Markov chain:
%
%   x -> z=A*x  -> y
%
% The input vector has iid components with a distribution set by the
% parameter inDist, which can be sparse Gaussian, Weibul or BPSK.
% The output y is generated by a componentwise measurement channel selected
% by the parameter outDist.  The output channel can be AWGN or a Poisson.
% Various forms of linear transformation A can be selected.
%
% The program runs ntest Monte-Carlo iterations and, for each instance,
% runs the methods specified in the vector methTest.  The methods can be
% sum-product generalized approximate message passing (GAMP_METH), 
% linear MMSE estimation (LMMSE_METH) and support-aware linear MMSE 
% estimation (LMMSE_GENIE_METH).  For all specified methods, the programs
% measures either mean-square error (MSE) or symbol error rate (SER).  For
% the G-AMP algorithm, the performance is measured per iteration.

% Set path
addpath('../main/');

% Simulation parameters
% ---------------------
ntest = 10;         % Number of Monte-Carlo tests
numiter = 1000;      % Number of iterations
nx = 256;           % Number of input components
nz = round(nx/4);  % Number of output components
newdat = 1; 	    % Set =1 to generate new data each test

% Matrix type
GAUSS_MAT = 1;      % Gaussian iid components
UNIF_MAT = 2;       % Positive uniform matrix
ZERO_ONE_MAT = 3;   % Zero-one matrix
SPARSE_MAT = 4;     % Sparse matrix
CGAUSS_MAT = 5;     % Circular Gaussian iid components
DFT_MAT_RAND = 6;   % A matrix computes a randomly-row-subsampled DFT
DFT_MAT_BLK = 7;    % A matrix computes a block-row-subsampled DFT
matrixType = DFT_MAT_RAND;

% Sparsity ratio on input
sparseRat = 0.02;        

% Non-sparse component of input distribution
GAUSS_IN = 1;         % Gaussian distribution
WEIBUL_IN = 2;        % Weibul distribution
BPSK_IN = 3;          % BPSK distribution
CGAUSS_IN = 4;          % Circular Gaussian distribution
inDist = CGAUSS_IN;     % Input distribution

% Output distribution
GAUSS_OUT = 1;         % Gaussian distribution
POISSON_OUT = 2;       % Poisson dist
CGAUSS_OUT = 3;        % Circular Gaussian distribution
LOGIT_OUT = 4;         % Logistic output channel 
outDist = CGAUSS_OUT;   % Output distribution

% Performance metric
MSE_PERF = 1;   % Measure mean-squared error
SER_PERF = 2;   % Measure symbol error rate (P(xhat(j) \neq x(j))
perfMetric = MSE_PERF;

% Methods to test
GAMP_METH = 1;
LMMSE_METH = 2;
LMMSE_GENIE_METH = 3;
methStr = {'gamp', 'lmmse', 'lmmse-genie'};
methTest = [GAMP_METH LMMSE_METH LMMSE_GENIE_METH];
nmeth = length(methTest);

% G-AMP parameters.  See class GampOpt
opt = GampOpt();        % default parameters
opt.nit = numiter;      % number of iterations
%opt.pvarMin = 1e-10;
%opt.xvarMin = 1e-10;
opt.adaptStep = 1;
%opt.stepWindow = 0;								
opt.uniformVariance = 0;	
opt.tol = -1;          % stopping tolerance 
opt.stepIncr = 1.1;	% multiplicative step increase
opt.stepMax = 0.3;	% max step 			
opt.step = 0.01;	% initial step 
%opt.stepMin = 0.01;	% min step
%opt.stepTol = -1;       % stopping tolerance based on step
opt.pvarStep = 1;	% apply step to pvar? 					
opt.varNorm = 0;	% normalize the variances? 

%opt.xvar0 = 1e-3;						
%opt.xhat0 = (randn(nx,2)*[1;1j])/sqrt(2);
%opt.xvar0 = mean(abs(opt.xhat0-xmean0s).^2)+xvar0s;

% Generate input distribution
% ----------------------------
switch (inDist)
    case GAUSS_IN
        xmean0 = 0;
        xvar0 = 1;
        inputEst0 = AwgnEstimIn(xmean0, xvar0);
    case CGAUSS_IN
        xmean0 = 0;
        xvar0 = 1;
        inputEst0 = CAwgnEstimIn(xmean0, xvar0);
    case BPSK_IN
        xmax = 1;       % Max value
        x0 = [-xmax xmax]';
        px0 = 0.5*[1 1]';
        inputEst0 = DisScaEstim(x0, px0);
    case WEIBUL_IN
        kx = 0.5;       % Stretch parameter
        lambdax = 1;    % Shape parameter
        xmax = 10;
        nx0 = 100;
        [x0,px0] = Weibull(kx, lambdax, xmax, nx0);
        inputEst0 = DisScaEstim(x0,px0);
end

% Modify distribution to include sparsity
if (sparseRat < 1)
    inputEst = SparseScaEstim( inputEst0, sparseRat );
else
    inputEst = inputEst0;
end

% For measuring SER, get all possible constellation points
if (perfMetric == SER_PERF)
    x0 = inputEst.getPoints();
end

% Get mean and variance after sparsification
[xmean0s, xvar0s] = inputEst.estimInit;

% Output distribution
% --------------------
if (outDist == GAUSS_OUT) || (outDist == CGAUSS_OUT)
    snr = 20;                       % SNR 
    wmean = 0;                      % Noise mean
    wvar = 10.^(-0.1*snr)*sparseRat*(abs(xmean0)^2+xvar0);    % Noise variance
    if (matrixType == DFT_MAT_BLK)||(matrixType == DFT_MAT_RAND)
      wvar = wvar*(nx/nz);	% DFT_MAT normalized differently
    end;
    if (outDist == GAUSS_OUT) && ((matrixType == DFT_MAT_BLK) ...
    			||(DFT_MAT_RAND)||(matrixType == CGAUSS_MAT)),
        outDist = CGAUSS_OUT;
	warning('Forcing outDist=CGAUSS_OUT because matrix is complex-valued')
    end;
elseif (outDist == POISSON_OUT)
    snr = 20;  % Output SNR
    poisson_scale = 10^(0.1*snr);
elseif (outDist == LOGIT_OUT)
    logitScale = 10;
end

% Initialize vectors
metricMeth = nan(ntest, nmeth);
metricGAMP = nan(numiter, ntest);
val = nan(numiter, ntest);
beta = nan(numiter, ntest);

for itest = 1:ntest
    
    if (newdat)
        % Generate random input vector
        x = inputEst.genRand(nx);
        
        % Generate random matrix and transform output z
        if (matrixType == GAUSS_MAT)
            a0 = 0;
            A = 1/sqrt(nx).*(randn(nz,nx) + a0);
            Aop = MatrixLinTrans(A);
        elseif (matrixType == CGAUSS_MAT)
            a0 = 0;
            A = 1/sqrt(nx).*...
                (sqrt(1/2)*randn(nz,nx) + sqrt(1/2)*1j*randn(nz,nx) + a0);
            Aop = MatrixLinTrans(A);
        elseif (matrixType == UNIF_MAT)
            A = 1/sqrt(nx).*rand(nz,nx);
            Aop = MatrixLinTrans(A);
        elseif (matrixType == ZERO_ONE_MAT)
            A = 1/sqrt(nx)*(rand(nz,nx) > 0.5);
            Aop = MatrixLinTrans(A);
        elseif (matrixType == SPARSE_MAT)
            d = 10;
            A = genSparseMat(nz,nx,d);
            Aop = MatrixLinTrans(A);
        elseif (matrixType == DFT_MAT_BLK)||(matrixType == DFT_MAT_RAND)
            domain = true; %set to false for IDFT
            Aop = FourierLinTrans(nx,nx,domain);
            if (matrixType == DFT_MAT_RAND),
              Aop.ySamplesRandom(nz); %randomly subsample the DFT matrix
	    else %matrixType == DFT_MAT_BLK
	      start_indx = ceil((nx-nz)*rand(1));
              Aop.ySamplesBlock(nz,start_indx); %block-subsample the DFT matrix
	    end;
	    if (sum(methTest==LMMSE_METH))||(sum(methTest==LMMSE_GENIE_METH)),
	      I = eye(nx);
	      A = nan(nz,nx); for indx=1:nx, A(:,indx) = Aop.mult(I(:,indx)); end;
	    end;
        end
        
        % Generate output
        z = Aop.mult(x);
        if (outDist == GAUSS_OUT)
            w = wmean + sqrt(wvar)*randn(nz,1);
            y = z + w;
            outputEst = AwgnEstimOut(y, wvar);
        elseif (outDist == CGAUSS_OUT)
            w = wmean + sqrt(wvar/2)*(randn(nz,1) + 1j*randn(nz,1));
            y = z + w;
            outputEst = CAwgnEstimOut(y, wvar);
        elseif (outDist == POISSON_OUT)
            y = poissrnd(poisson_scale*z);
            outputEst = PoissonEstim(y, repmat(poisson_scale,nz,1));
        elseif (outDist == LOGIT_OUT)
            py0 = 1./(1+exp(logitScale*z));  % Prob that y=0
            y = (rand(nz,1) > py0);
            outputEst = LogitEstimOut(y,logitScale);
        end
	snr_actual = 20*log10(norm(z)/norm(w));
    end%newdat
    
    % Loop over methods
    for imeth = 1:nmeth
        
        meth = methTest(imeth);
        if (meth == GAMP_METH)

%opt.xhat0 = x+0.1*randn(nx,2)*[1;1j]; opt.xvar0 = 1e-6; % test genie initialization

            % Call the G-AMP algorithm
            % The function returns xhatTot(i,t) = estimate of x(i) on iteration t.
            % So, xhatTot(:,end) is the final estimate
            [xhat, xvar, rhat, rvar, shatFinal, svarFinal,zhatFinal,zvarFinal, estHist] = ...
                gampEst(inputEst, outputEst, Aop, opt);
            xhatGAMP = xhat;
            xhatTot = estHist.xhat;
            val(1:length(estHist.val),itest) = estHist.val;
	    val(length(estHist.val)+1:end,itest) = val(length(estHist.val),itest);
            beta(1:length(estHist.step),itest) = estHist.step;
	    beta(length(estHist.val)+1:end,itest) = beta(length(estHist.val),itest);
      
        elseif (meth == LMMSE_METH)
            
            % Compute LMMSE solution
            if (outDist == GAUSS_OUT) || (outDist == CGAUSS_OUT)
                xhat = (wvar.*eye(nx) + xvar0s.*A'*A ...
			) \ (xvar0s.* A'*(y-A*ones(nx,1)*xmean0s)) + xmean0s;
            elseif (outDist == POISSON_OUT)
                zmean = A*repmat(xmean0s,nx,1);
                xhat = xvar0s*A'* ((diag(zmean) + ...
			poisson_scale*xvar0s.*A*A') \ (y-poisson_scale*zmean)) + xmean0s;
            end
            xhatLMMSE = xhat;

        elseif (meth == LMMSE_GENIE_METH)

            % Compute support-aware MMSE solution
	    supp = find(x~=0);
	    ns = length(supp);
	    As = A(:,supp);
	    xhat = zeros(nx,1);
            if (outDist == GAUSS_OUT) || (outDist == CGAUSS_OUT)
                xhat(supp) = (wvar.*eye(ns) + xvar0.*As'*As ...
			) \ (xvar0.* As'*(y-As*ones(ns,1)*xmean0)) + xmean0;
            elseif (outDist == POISSON_OUT)
                zmean = As*repmat(xmean0,ns,1);
                xhat(supp) = xvar0*As'* ((diag(zmean) + ...
			poisson_scale*xvar0.*As*As') \ (y-poisson_scale*zmean)) + xmean0;
            end
            xhatGENIE = xhat;

        end
        
        % Measure error per iteration
        if (perfMetric == MSE_PERF)
            metricMeth(itest,imeth) = 10*log10( mean(abs(xhat-x).^2) );
            if (meth == GAMP_METH)
                dx = xhatTot - repmat(x,1,size(xhatTot,2));
                metricGAMP(1:size(dx,2),itest) = 10*log10( mean( abs(dx).^2 )' );
                metricGAMP(size(dx,2)+1:end,itest) = metricGAMP(size(dx,2),itest);
            end
            fprintf(1,'it=%d %s mse=%f\n', itest, methStr{meth}, metricMeth(itest,imeth));
            
        elseif (perfMetric == SER_PERF)
            
            metricMeth(itest,imeth) = measSER(xhat, x, x0);
            if (meth == GAMP_METH)
                metricGAMP(:,itest) = measSER(xhatTot, x, x0);
            end
            % Display results
            fprintf(1,'it=%d %s ser=%f\n', itest, methStr{meth}, metricMeth(itest,imeth));
            
        end
        
        %if ~newdat
        %    return
        %end
    end
    
end

% Compute and plot mean error by iteration
figure(1)
clf
for imeth = 1:nmeth
    if (methTest(imeth) == GAMP_METH)
        metricGAMPmean = mean( metricGAMP, 2 );
	subplot(413)
          plot((1:numiter), mean( beta,2 ), '.-'); ylabel('step'); grid on;
	  %axe = axis; axis([axe(1:2),min(beta)*0.9,max(beta)*1.1])
	subplot(414)
          semilogy((1:numiter), mean( -val,2 ), '.-'); ylabel('-val'); grid on;
	  %axe = axis; axis([axe(1:3),max(val)+(max(val)-min(val(val~=-inf)))/10])
	subplot(211)
          plot((1:numiter), metricGAMPmean, '-');
    elseif (methTest(imeth) == LMMSE_METH)
        metricMean = mean( metricMeth(:,imeth) );
        plot([1 numiter], metricMean*[1 1], 'g--');
    elseif (methTest(imeth) == LMMSE_GENIE_METH)
        metricMean = mean( metricMeth(:,imeth) );
        plot([1 numiter], metricMean*[1 1], 'r-.');
    end
    hold on;
end
hold off;
grid on;
xlabel('Iteration');
legend(methStr(methTest),'location','best')
if (perfMetric == SER_PERF)
    ylabel('Symbol error rate');
    axis([1 numiter 1e-4 0.1]);
else
    ylabel('MSE (dB)');
end

% Plot final estimates
figure(2)
clf
subplot(311)
  stem(abs(xhatGENIE)); ylabel('GENIE'); grid on;
  hold on; plot(abs(x),'r+'); hold off;
  legend('estimate','true');
  title('final estimates')
subplot(312)
  stem(abs(xhatGAMP)); ylabel('GAMP'); grid on;
  hold on; plot(abs(x),'r+'); hold off;
  legend('estimate','true');
subplot(313)
  stem(abs(xhatLMMSE)); ylabel('LMMSE'); grid on;
  hold on; plot(abs(x),'r+'); hold off;
  legend('estimate','true');
