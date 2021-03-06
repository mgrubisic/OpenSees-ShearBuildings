%############################# test_Strongback.m ##############################%
%                                                                              %
% Script for testing the functioning of the Strongback model.                  %
%                                                                              %
%                                                                              %
%                                                                              %
%                                                                              %
%                                                                              %
%##############################################################################%

clear all; close all; clc; %#ok<CLALL>

%################################# Definition #################################%
nStories = 6;
bldg = Strongback(nStories);
bldg.seismicDesignCategory = 'Dmax';

%----------------------------- Units and constants ----------------------------%
bldg.units.force = 'kip';
bldg.units.mass  = 'kslug';
bldg.units.length= 'ft';
bldg.units.time  = 'sec';

bldg.g = 32.2;       % Acceleration due to gravity

bldg.seismicDesignCategory = 'Dmax';
bldg.respModCoeff = 8;
bldg.deflAmplFact = 8;
bldg.overstrengthFactor = 3;
bldg.impFactor = 1;

%------------------------------ Story definition ------------------------------%
storyHeight = 15;
firstHeight = 20;
storyDL     = 0.080;
roofDL      = 0.030;
storyArea   = 90*90;

bldg.storyHeight    = ones(1,nStories)*storyHeight;
bldg.storyHeight(1) = firstHeight;

storyDL        = ones(1,nStories)*storyDL;
storyDL(end)   = roofDL;
bldg.storyMass = (storyDL*storyArea)/bldg.g;

springGivens.as       =  0.03;  % strain hardening ratio
springGivens.Lambda_S = 10.00;  % Cyclic deterioration parameter - strength
springGivens.Lambda_K = 10.00;  % Cyclic deterioration parameter - stiffness
springGivens.c_S      =  1.00;  % rate of deterioration - strength
springGivens.c_K      =  1.00;  % rate of deterioration - stiffness
springGivens.Res      =  0.30;  % residual strength ratio (relative to yield)
springGivens.D        =  1.00;  % rate of cyclic deterioration
springGivens.nFactor  =  0.00;  % elastic stiffness amplification factor
springGivens.C_yc     =  0.80;  % ratio of yield strength to capping strength
springGivens.C_upc    = 20.00;  % ratio of ultimate deflection to u_y + u_p + u_pc
springGivens.ad       =  0.10;  % deterioration stiffness ratio -- higher values mean faster deterioration
springGivens.includePDelta = false;

springGivens.stiffnessSafety = 1.0;
springGivens.strengthSafety  = 1.0;

springGivens.enforceMinimumStiffness = false;
springGivens.enforceMinimumStrength = false;
springGivens.minimumRatio = 0.7;

targetTrussDeformation = 0.002;  % Ratio of story height
bldg.storyTrussDefinition = cell(nStories,1);
trussModulus = (cumsum(bldg.storyMass,'reverse')*bldg.g)/targetTrussDeformation;
for i = 1:nStories
    bldg.storyTrussDefinition{i} = sprintf('uniaxialMaterial Elastic %i %g',i+10,trussModulus(i));
end

bldg.strongbackDefinition.Area    = 1;
bldg.strongbackDefinition.Modulus = 1e3;
bldg.strongbackDefinition.Inertia = 1e3;

%----------------------------------- Options ----------------------------------%
bldg.echoOpenSeesOutput = false;
bldg.deleteFilesAfterAnalysis = false;

paths = fieldnames(pathOf);
for i = 1:length(paths)
    bldg.pathOf.(paths{i}) = pathOf.(paths{i});
end
bldg.pathOf.tclfunctions = '/home/petertalley/Github/OpenSees-ShearBuildings/lib';

bldg.optionsPushover.maxDrift = sum(bldg.storyHeight);
bldg.optionsPushover.test.print = 0;

bldg.optionsIDA.nMotions = 2;

gm_mat = '../ground_motions.mat';

%################################# Run tests! #################################%
R_max = 8;
R_min = 1;
R_tolerance = 0.25;

EI = zeros(7,1);
R = ones(7,1)*R_max;
for i = 1:length(EI)
    bldg.strongbackDefinition.Modulus = sqrt(EI(i));
    bldg.strongbackDefinition.Inertia = sqrt(EI(i));

    R_failure = R_max;
    R_success = R_min;

    complete = false;
    failure = false;
    maxed_out = false;

    while ~complete
        fprintf('Evaluating R = %g\n', bldg(1).respModCoeff)
        for archIndex = 1:nArchetypes
            ELF = equivalentLateralForceAnalysis(bldg(archIndex));
            spring = bldg(archIndex).springDesign(ELF,springGivens);
            bldg(archIndex).storySpringDefinition = {spring.definition}';

            F = bldg(archIndex).pushoverForceDistribution();
            pushover = bldg(archIndex).pushover(F,'TargetPostPeakRatio',0.79);
            pushover = bldg(archIndex).processPushover(pushover,ELF);

            IDA(archIndex) = incrementalDynamicAnalysis(bldg(archIndex), gm_mat, pushover.periodBasedDuctility);
        end
        fprintf('ACMR = %g; ACMR20 = %g\n', IDA.ACMR, IDA.ACMR20)

        if IDA.ACMR > IDA.ACMR20
            success = true;
        else
            success = false;
        end

        if success
            if bldg.respModCoeff == R_max
                complete = true;
                maxed_out = true;
            elseif (bldg.respModCoeff - R_success) < R_tolerance
                complete = true;
            else
                R_success = bldg.respModCoeff;
                bldg.respModCoeff = R_success + (R_failure - R_success)/2;
            end
        else
            if (bldg.respModCoeff - R_min) < R_tolerance
                complete = true;
                failure = true;
            else
                R_failure = bldg.respModCoeff;
                bldg.respModCoeff = R_success + (R_failure - R_success)/2;
            end
        end
    end

    if failure
        fprintf('\nAnalysis failed; R too small: %g\n', bldg.respModCoeff)
    else
        fprintf('\nAnalysis complete; R = %g\n', bldg.respModCoeff)
    end

    if maxed_out
        fprintf('Maxed out R; ACMR only goes up from here\n')
        break
    end

    R(i) = bldg.respModCoeff;
end
