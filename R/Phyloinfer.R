#### Elliptical slice sampler by Murray et~al (2010) ####

# inputs:
#   q_cur: initial state of the parameter
#   l_cur: initial log-likelihood
#   loglik: log-likelihood function of q
#   cholC: Cholesky decomposition (upper triangular matrix) of covariance matrix of Gaussian prior
# outputs:
#   q: new state of the parameter following N(q;0,Cov)*lik
#   l: log-likelihood of new state
#   Ind: proposal acceptance indicator

ESS = function(q_cur, l_cur, loglik, cholC)
{  
  # choose ellipse
  nu = t(cholC)%*%rnorm(length(q_cur))
  
  # log-likelihood threshold
  u = runif(1)
  logy <- l_cur + log(u)
  
  # draw a initial proposal, also defining a bracket
  t = 2*pi*runif(1)
  t_min <- t-2*pi; t_max <- t
  
  while(1)
  {
    q <- q_cur*cos(t) + nu*sin(t)
    l = loglik(q)
    if(l>logy) return(list(q=q,l=l,Ind=1))
    # shrink the bracket and try a new point
    if(t<0) t_min <- t
    else t_max <- t
    t = runif(1,t_min,t_max)
  }
}

#### Metropolis-Adjusted Langevin (MALA) Algorithm ####
# This function generates one sample given previous state.

# inputs:
#   q_cur: initial state of the parameter
#   u_cur, du_cur: initial potential energy and its gradient
#   U:=-log(density(q)), potential function of q, or its gradient
#   eps: step size
# outputs:
#   q: new state of the parameter
#   u, du: new potential energy and its gradient
#   Ind: proposal acceptance indicator

MALA = function (q_cur, u_cur, du_cur, U, eps=.2)
{
  # initialization
  q = q_cur
  D = length(q)
  u = u_cur
  du = du_cur
  
  # sample momentum
  p = rnorm(D)
  
  # calculate current energy
  E_cur = u + sum(p^2)/2
  
  # Make a half step for momentum
  p = p - eps/2 * du
  
  # Make a full step for the position
  q = q + eps * p
  
  du = U(q,T)
  # Make a half step for momentum at the end
  p = p - eps/2 * du
  
  # Evaluate potential and kinetic energies at start and end of trajectory
  u = U(q)
  E_prp = u + sum(p^2)/2
  
  # Accept or reject the state at end of trajectory, returning either
  # the position at the end of the trajectory or the initial position
  logAP = -E_prp + E_cur
  
  if( is.finite(logAP)&&(log(runif(1))<min(0,logAP)) ) 
    return (list(q = q, u = u, du = du, Ind = 1))
  else 
    return (list(q = q_cur, u = u_cur, du = du_cur, Ind = 0))
}

#### adaptive Metropolis-Adjusted Langevin (aMALA) Algorithm ####
# This is adaptive block updating GMRF by Knorr-Held and Rue (2002), equivalent to Riemannian MALA by Girolami and Calderhead (2011).
# This function generates one sample given previous state.

# inputs:
#   q_cur: initial state of the parameter
#   u_cur: initial potential energy
#   U:=-log(density(q)), potential function of q, or its gradient
#   Met: Fisher observed(or expected) information matrix of approximating Normal
#   c: parameter to control step size of kappa
#   eps: step size
#   L: number of leapfrogs
# outputs:
#   q: new state of the parameter
#   u: new potential energy
#   Ind: proposal acceptance indicator

aMALA = function (q_cur, u_cur, U, Met, c, eps=1)
{
  # initialization
  q = q_cur
  D = length(q)
  
  # sample kappa
  repeat
  {
    t=runif(1,1/c,c)
    if(runif(1)<(t+1/t)/(c+1/c))
      break
  }
  q[D]=q[D]*t
  
  # prepare pre-conditional matrix and gradient
  Q=Met(q)
  cholQ=chol(Q)
  g=U(q,T)
  
  # sample momentum
  z=rnorm(D-1)
  p=backsolve(cholQ,z)
  
  # log proposal density
  logprp = -t(z)%*%z/2+sum(log(diag(cholQ)))
  
  # update momentum
  #	p=p-eps/2*solve(Q,g[-D])
  p = p-eps/2*(chol2inv(cholQ)%*%g[-D])
  
  # update position
  q[-D] = q[-D]+eps*p
  
  # update pre-conditional matrix and gradient
  Q = Met(c(q[-D],q_cur[D]))
  cholQ=chol(Q)
  g = U(c(q[-D],q_cur[D]),T) # very interesting update!!!
  
  # update momentum
  p = p-eps/2*(chol2inv(cholQ)%*%g[-D])
  
  # log reverse proposal density
  logprp_rev = -t(p)%*%Q%*%p/2+sum(log(diag(cholQ)))
  
  # Evaluate potential energy
  u = U(q)
  
  # Accept or reject the state jointly
  logAP = -u + u_cur - logprp + logprp_rev
  
  if ( is.finite(logAP) && (log(runif(1))<min(0,logAP)) )
    return (list(q = q, u = u, Ind = 1))
  else
    return (list(q = q_cur, u = u_cur, Ind = 0))
}

#### Hamiltonian Monte Carlo ####
# This is standard HMC method.
# This function generates one sample given previous state

# inputs:
#   q_cur: initial state of the parameter
#   u_cur, du_cur: initial potential energy and its gradient
#   U:=-log(density(q)), potential function of q, or its gradient
#   eps: step size
#   L: number of leapfrogs
# outputs:
#   q: new state of the parameter
#   u, du: new potential energy and its gradient
#   Ind: proposal acceptance indicator

HMC = function (q_cur, u_cur, du_cur, U, eps=.2, L=5)
{  
  # initialization
  q = q_cur
  D = length(q)
  u = u_cur
  du = du_cur
  
  # sample momentum
  p = rnorm(D)
  
  # calculate current energy
  E_cur = u + sum(p^2)/2
  
  # Make a half step for momentum at the beginning
  p = p - eps/2 * du
  
  randL = ceiling(runif(1)*L)
  # Alternate full steps for position and momentum
  for (l in 1:randL)
  {
    # Make a full step for the position
    q = q + eps * p
    
    du = U(q,T)
    # Make a full step for the momentum, except at end of trajectory
    if (l!=randL)
      p = p - eps * du
  }
  
  # Make a half step for momentum at the end.
  p = p - eps/2 * du
  
  # Evaluate potential and kinetic energies at start and end of trajectory
  u = U(q)
  E_prp = u + sum(p^2)/2
  
  # Accept or reject the state at end of trajectory, returning either
  # the position at the end of the trajectory or the initial position
  logAP = -E_prp + E_cur
  
  if( is.finite(logAP) && (log(runif(1))<min(0,logAP)) )
    return (list(q = q, u = u, du = du, Ind = 1))
  else
    return (list(q = q_cur, u = u_cur, du = du_cur, Ind = 0))
}

#### Split Hamiltonian Monte Carlo ####
# This is splitHMC method by (Gaussian) approximation.
# This function generates one sample given previous state.

# inputs:
#   q_cur: initial state of the parameter
#   u_cur, du_cur: initial potential energy and its gradient
#   U:=-log(density(q)), potential function of q, or its gradient
#   rtEV, EVC: square root of eigen-valudes, eigen-vectors of Fisher observed(or expected) information matrix of approximating Normal
#   eps: step size
#   L: number of leapfrogs
# outputs:
#   q: new state of the parameter
#   u, du: new potential energy and its gradient
#   Ind: proposal acceptance indicator

splitHMC = function (q_cur, u_cur, du_cur, U, rtEV, EVC, eps=.1, L=5)
{
  # initialization
  q = q_cur
  D = length(q)
  u = u_cur
  du = du_cur
  
  # sample momentum
  p = rnorm(D)
  
  # calculate current energy
  E_cur = u + sum(p^2)/2
  
  
  randL = ceiling(runif(1)*L)
  p = p - eps/2*du
  qT = rtEV*(t(EVC)%*%q[-D])
  pT = t(EVC)%*%p[-D]
  A = t(qT)%*%qT
  # Alternate full steps for position and momentum
  for (l in 1:randL)
  {
    p[D] <- p[D] - eps/2*A/2*exp(q[D])
    q[D] <- q[D] + eps/2*p[D]
    
    # Make a full step for the middle dynamics
    Cpx = complex(mod=1,arg=-rtEV*exp(q[D]/2)*eps)*complex(re=qT*exp(q[D]/2),im=pT)
    qT = Re(Cpx)*exp(-q[D]/2)
    pT = Im(Cpx)
    q[-D] = EVC%*%(qT/rtEV)
    
    # Make a half step for the last half dynamics
    A=t(qT)%*%qT
    
    q[D] <- q[D] + eps/2*p[D]
    p[D] <- p[D] - eps/2*A/2*exp(q[D])
    
    du = U(q,T)
    if(l!=randL)
    {
      pT = pT - eps*(t(EVC)%*%du[-D])
      p[D] = p[D] - eps*du[D]
    }
  }
  p[-D] = EVC%*%pT - eps/2*du[-D]
  p[D] = p[D] - eps/2*du[D]
  
  # Evaluate potential and kinetic energies at start and end of trajectory
  u = U(q)
  E_prp = u + sum(p^2)/2
  
  # Accept or reject the state at end of trajectory, returning either
  # the position at the end of the trajectory or the initial position
  logAP = -E_prp + E_cur
  
  if( is.finite(logAP) && (log(runif(1))<min(0,logAP)) )
    return (list(q = q, u = u, du = du, Ind = 1))
  else
    return (list(q = q_cur, u = u_cur, du = du_cur, Ind = 0))
}

#### Sampling wrappers ####

# This serves as a black box to sample distributions using HMC algorithms provided data and basic settings. #

sampling = function(data, para, alg, setting, init, print=TRUE)
{
  # pass the data and parameters
  lik_init = data$lik_init # f_offset = data$f_offset
  Ngrid = lik_init$ng+1
  alpha = para$alpha
  beta = para$beta
  invC = para$invC
  rtEV = para$rtEV
  EVC = para$EVC
  cholC = para$cholC
  
  # MCMC sampling setting
  stepsz = setting$stepsz
  Nleap  = setting$Nleap
  if(alg=='aMALA')
    szkappa=setting$szkappa
  
  # storage of posterior samples
  NSAMP = setting$NSAMP
  NBURNIN = setting$NBURNIN
  SAMP = matrix(NA,NSAMP-NBURNIN,Ngrid) # all parameters together
  acpi = 0
  acpt = 0
  
  # initialization
  theta = init$theta
  u = init$u
  du = init$du
  
  # start MCMC run
  start_time = Sys.time()
  cat('Running ', alg ,' sampling...\n')
  for(Iter in 1:NSAMP)
  {  
    if(print&&Iter%%100==0)
    {
      cat(Iter, ' iterations have been finished!\n' )
      cat('Online acceptance rate is ',acpi/100,'\n')
      acpi=0
    }
    
    # sample the whole parameter
    tryCatch({res=switch(alg,
                         HMC=eval(parse(text='HMC'))(theta,u,du,function(theta,grad=F)U(theta,lik_init,invC,alpha,beta,grad),stepsz,Nleap),
                         splitHMC=eval(parse(text='splitHMC'))(theta,u,du,function(theta,grad=F)U_split(theta,lik_init,invC,alpha,beta,grad),rtEV,EVC,stepsz,Nleap),
                         MALA=eval(parse(text='MALA'))(theta,u,du,function(theta,grad=F)U(theta,lik_init,invC,alpha,beta,grad),stepsz),
                         aMALA=eval(parse(text='aMALA'))(theta,u,function(theta,grad=F)U_kappa(theta,lik_init,invC,alpha,beta,grad),function(theta)Met(theta,lik_init,invC),szkappa,stepsz),
                         ESS=eval(parse(text='ESS'))(theta[-Ngrid],u,function(f)coal_loglik(lik_init,f),cholC/sqrt(theta[Ngrid])),
                         stop('The algorithm is not in the list!'));
              theta[1:(Ngrid-(alg=='ESS'))]=res$q;u=res[[2]];if(any(grepl(alg,c('HMC','splitHMC','MALA'))))du=res$du;
              acpi=acpi+res$Ind}, error=function(e){cat("ERROR :",conditionMessage(e), "\n")})
    # Gibbs sample kappa for ESS
    if(alg=='ESS')
      theta[Ngrid]=rgamma(1,alpha+(Ngrid-1)/2,beta+t(theta[-Ngrid])%*%invC%*%theta[-Ngrid]/2)
    
    # save posterior samples after burnin
    if(Iter>NBURNIN)
    {
      SAMP[Iter-NBURNIN,]<-theta
      acpt<-acpt+res$Ind
    }
    
  }
  stop_time = Sys.time()
  time = stop_time-start_time
  cat('\nTime consumed : ',time)
  acpt = acpt/(NSAMP-NBURNIN)
  cat('\nFinal Acceptance Rate: ',acpt,'\n')
  
  return(list(SAMP=SAMP,time=time,acpt=acpt))
}

# Same as 'sampling' above but specially designed for comparing mixing rate of MCMC algorithms #

sampling_mixrate = function(data, para, alg, setting, init, print=TRUE)
{
  # pass the data and parameters
  lik_init = data$lik_init # f_offset = data$f_offset
  Ngrid = lik_init$ng+1
  alpha = para$alpha
  beta = para$beta
  invC = para$invC
  rtEV = para$rtEV
  EVC = para$EVC
  cholC = para$cholC
  
  # MCMC sampling setting
  stepsz = setting$stepsz
  Nleap  = setting$Nleap
  if(alg=='aMALA')
    szkappa=setting$szkappa
  
  # storage of posterior samples
  WallTime = setting$WallTime
  Intvl = setting$Intvl
  SaveLeng = ceiling(WallTime/Intvl)
  acpi = 0
  acpt = 0
  
  # save for comparing mixing rate
  logLiks = rep(NA,SaveLeng) # save all the log-likelihoods
  times = rep(NA,SaveLeng) # save all time intervals
  
  # initialization
  theta = init$theta
  u  = init$u
  du = init$du
  times[1] = 0
  logLiks[1] = coal_loglik(lik_init,theta[-Ngrid])
  
  # start MCMC run
  start_time = Sys.time()
  cat('Running ', alg ,' sampling...\n')
  Iter=1
  counter=1
  while(counter<=SaveLeng&times[counter]<=WallTime)
  {    
    if(print&&Iter%%100==0)
    {
      cat(Iter, ' iterations have been finished!\n' )
      cat('Online acceptance rate is ',acpi/100,'\n')
      acpi=0
    }
    
    # sample the whole parameter
    tryCatch({res=switch(alg,
                         HMC=eval(parse(text='HMC'))(theta,u,du,function(theta,grad=F)U(theta,lik_init,invC,alpha,beta,grad),stepsz,Nleap),
                         splitHMC=eval(parse(text='splitHMC'))(theta,u,du,function(theta,grad=F)U_split(theta,lik_init,invC,alpha,beta,grad),rtEV,EVC,stepsz,Nleap),
                         MALA=eval(parse(text='MALA'))(theta,u,du,function(theta,grad=F)U(theta,lik_init,invC,alpha,beta,grad),stepsz),
                         aMALA=eval(parse(text='aMALA'))(theta,u,function(theta,grad=F)U_kappa(theta,lik_init,invC,alpha,beta,grad),function(theta)Met(theta,lik_init,invC),szkappa,stepsz),
                         ESS=eval(parse(text='ESS'))(theta[-Ngrid],u,function(f)coal_loglik(lik_init,f),cholC/sqrt(theta[Ngrid])),
                         stop('The algorithm is not in the list!'));
              theta[1:(Ngrid-(alg=='ESS'))]=res$q;u=res[[2]];if(any(grepl(alg,c('HMC','splitHMC','MALA'))))du=res$du;
              acpi=acpi+res$Ind}, error=function(e){cat("ERROR :",conditionMessage(e), "\n")})
    # Gibbs sample kappa for ESS
    if(alg=='ESS')
      theta[Ngrid]=rgamma(1,alpha+(Ngrid-1)/2,beta+t(theta[-Ngrid])%*%invC%*%theta[-Ngrid]/2)
    
    # save acceptance rate
    acpt<-acpt+res$Ind
    
    cur_time=as.numeric(Sys.time()-start_time,units='secs')
    if(cur_time-times[counter]>Intvl)
    {
      counter=counter+1
      times[counter]=cur_time
      logLiks[counter]=coal_loglik(lik_init,theta[-Ngrid])
    }
    Iter = Iter+1;
  }
  stop_time = Sys.time()
  time = stop_time-start_time
  cat('\nTime consumed : ',time)
  acpt = acpt/Iter
  cat('\nFinal Acceptance Rate: ',acpt,'\n')
  
  return(list(time=time,acpt=acpt,WallTime=WallTime,Intvl=Intvl,logLiks=logLiks,times=times))
}