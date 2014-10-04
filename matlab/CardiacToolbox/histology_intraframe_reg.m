function [tParam, regParam] = histology_intraframe_reg(pathstr, files, opts)
% histology_intraframe_reg  Registration diffusion of histology slices.
%
% histology_intraframe_reg computes the registration of each slices to the
% two adjacent slices. The two resulting transforms are combined to
% produce a compromise transform. The process is applied iteratively.
%
% [TPARAM, REGPARAM] = histology_intraframe_reg(PATHSTR, FILES)
%
%   PATHSTR is the full path to the files. If empty, PATHTOFILES='.'.
%
%   FILES is the result of a dir() command, e.g. dir('*.png'). The
%   function expects a list of histology images.
%
% ... = histology_intraframe_reg(..., OPTS)
%
%   OPTS is a struct with algorithm parameters:
%
%     'MaxIter':   (def 10) Maximum number of diffusion iterations.
%
%     'DiffusionCoefficient': (def 0.4) Value of diffusion coefficient.
%
%     'verbose':   (default 0) Show elastix output on the screen.
%
%     'T0':        (default []) Initial transform in elastix format for the
%                  images (typically rigid transforms to provide an initial
%                  rough alignment).
%
% See also: histology_preprocessing.

% Author: Ramon Casero <rcasero@gmail.com>
% Copyright © 2014 University of Oxford
% Version: 0.2.0
% $Rev$
% $Date$
% 
% University of Oxford means the Chancellor, Masters and Scholars of
% the University of Oxford, having an administrative office at
% Wellington Square, Oxford OX1 2JD, UK. 
%
% This file is part of Gerardus.
%
% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details. The offer of this
% program under the terms of the License is subject to the License
% being interpreted in accordance with English Law and subject to any
% action against the University of Oxford being under the jurisdiction
% of the English Courts.
%
% You should have received a copy of the GNU General Public License
% along with this program.  If not, see <http://www.gnu.org/licenses/>.

% check arguments
narginchk(2, 3);
nargoutchk(0, 4);

if (length(files) < 3)
    error('At least three files are needed for registration')
end

% defaults
if (nargin < 3 || isempty(opts) || ~isfield(opts, 'MaxIter'))
    opts.MaxIter = 10;
end
if (isempty(opts) || ~isfield(opts, 'DiffusionCoefficient'))
    opts.DiffusionCoefficient = 0.4;
end
if (isempty(opts) || ~isfield(opts, 'verbose'))
    opts.verbose = 0;
end
if (isempty(opts) || ~isfield(opts, 'T0'))
    opts.T0 = [];
end
if (isempty(pathstr))
    pathstr = '.';
end

if (~isempty(opts.T0) && (length(opts.T0) ~= length(files)))
    error('If opts.T0 initial transforms are provided, there must be one per image')
end

% create a struct with the registration parameters
regParam = generate_registration_parameters();

% create a duplicate of the images that we will deform repeteadly in the
% diffusion process
pathtemp = tempname;
mkdir(pathtemp);
for I = 1:length(files)
    copyfile([pathstr filesep files(I).name], ...
        [pathtemp filesep files(I).name]); 
end

% diffusion computation loop
for S = 1:opts.MaxIter

    % initial transform to apply to images before registration in this
    % iteration
    if (S==1)
        
        T0 = opts.T0;
        
    else
        
        T0 = tParam;
        
    end
    
    % compute registration diffusion for the first slice of the histology
    % volume
    tic
    disp(['S = ' num2str(S) '/' num2str(opts.MaxIter) ...
        ', I = ' num2str(1) '/' num2str(length(files))])
    tParam(1) = process_extreme_slices(...
        [pathstr filesep files(2).name], ...
        [pathstr filesep files(1).name], ...
        T0(2), T0(1), regParam, opts);
    disp(['time = ' num2str(toc) 'sec'])
    
    
    % loop for all the other slices
    for I = 2:length(files)-1

        tic
        disp(['S = ' num2str(S) '/' num2str(opts.MaxIter) ...
            ', I = ' num2str(I) '/' num2str(length(files))])
        
        tParam(I) = process_intermediate_slices(...
            [pathstr filesep files(I-1).name], ...
            [pathstr filesep files(I).name], ...
            [pathstr filesep files(I+1).name], ...
            T0(I-1), T0(I), T0(I+1), regParam, opts);
        disp(['time = ' num2str(toc) 'sec'])

    end
    
    % compute registration diffusion for the last slice of the histology
    % volume
    tic
    disp(['S = ' num2str(S) '/' num2str(opts.MaxIter) ...
        ', I = ' num2str(length(files)) '/' num2str(length(files))])
    tParam(end) = process_extreme_slices(...
        [pathstr filesep files(end-1).name], ...
        [pathstr filesep files(end).name], ...
        T0(end-1), T0(end), regParam, opts);
    disp(['time = ' num2str(toc) 'sec'])

end

% delete temp files
rmdir(pathtemp, 's')

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% generate_registration_parameters()
%
%   Create a struct with the parameters necessary for registration
function regParam = generate_registration_parameters()

regParam.FixedInternalImagePixelType = 'float';
regParam.FixedImageDimension = 2;
regParam.MovingInternalImagePixelType = 'float';
regParam.MovingImageDimension = 2;
regParam.Registration = 'MultiMetricMultiResolutionRegistration';
regParam.FixedImagePyramid = {'FixedSmoothingImagePyramid', ...
    'FixedSmoothingImagePyramid', 'FixedSmoothingImagePyramid'};
regParam.MovingImagePyramid = {'MovingSmoothingImagePyramid', ...
    'MovingSmoothingImagePyramid', 'MovingSmoothingImagePyramid'};
regParam.Interpolator = {'BSplineInterpolator', 'BSplineInterpolator', ...
    'BSplineInterpolator'};
regParam.Metric = {'AdvancedMeanSquares', 'AdvancedMeanSquares', ...
    'AdvancedMeanSquares'};
regParam.Optimizer = 'RegularStepGradientDescent';
regParam.ResampleInterpolator = 'FinalBSplineInterpolator';
regParam.Resampler = 'DefaultResampler';
regParam.Transform = 'BSplineTransform';
regParam.AutomaticTransformInitialization = 'false';
regParam.AutomaticTransformInitializationMethod = 'GeometricalCenter';
regParam.UseFastAndLowMemoryVersion = 'true';
regParam.UseJacobianPreconditioning = 'false';
regParam.FiniteDifferenceDerivative = 'false';
regParam.MaximumNumberOfSamplingAttempts = 0;
regParam.ErodeMask = 'false';
regParam.NumberOfResolutions = 3;
regParam.FinalGridSpacingInVoxels = 16;
regParam.GridSpacingSchedule = [64 16 4];
regParam.HowToCombineTransforms = 'Compose';
regParam.UseDirectionCosines = 'true';
regParam.MaximumNumberOfIterations = 400;
regParam.MaximumStepLength = 50;
regParam.MinimumStepLength = 0.500;
regParam.MinimumGradientMagnitude = 1e-3;
regParam.NumberOfFixedHistogramBins = 32;
regParam.NumberOfMovingHistogramBins = 32;
regParam.NumberOfHistogramBins = 32;
regParam.FixedLimitRangeRatio = 0;
regParam.MovingLimitRangeRatio = 0;
regParam.FixedKernelBSplineOrder = 3;
regParam.MovingKernelBSplineOrder = 3;
regParam.ImageSampler = {'Full'  'Full'  'Full'};
regParam.FixedImageBSplineInterpolationOrder = 1;
regParam.UseRandomSampleRegion = 'false';
regParam.BSplineInterpolationOrder = 1;
regParam.FinalBSplineInterpolationOrder = 1;
regParam.DefaultPixelValue = 0;
regParam.WriteResultImage = 'true';
regParam.WriteResultImageAfterEachResolution = 'false';
regParam.WriteTransformParametersEachIteration = 'false';
regParam.WriteTransformParametersEachResolution = 'true';
regParam.ResultImagePixelType = 'unsigned char';
regParam.ResultImageFormat = 'png';
regParam.CompressResultImage = 'true';

end

% process_extreme_slices()
%
%   The first and last slices of the histology volume don't have slices on
%   both sides. This function deals with those two cases (it has to be run
%   twice, once for the first slice, and once for the last slice).
%
%   *M refers to the moving slice, i.e. the first or last histology slice.
%   *F refers to the fixed adjacent slice.
%
%   FILEM, FILEF is the path and filename to the histology images.
%
%   T0M, T0F is the nested (accumulated) transform to apply to each image
%   before registering them.
%
%   REGPARAM is the struct with the registration parameters for elastix.
%
%   OPTS is a struct with optional algorithm parameters.
function tm = process_extreme_slices(filef, filem, t0f, t0m, regParam, opts)

DEBUG = 0;

% load images
imm = imread(filem);
imf = imread(filef);

% preprocess histograms
[imm, imf] = histology_preprocessing(imm, imf);

% apply accumulated initial transform (make sure that added voxels are
% black, so that they blend in with the background)
t0m.DefaultPixelValue = 0;
t0f.DefaultPixelValue = 0;
imm = transformix(t0m, imm);
imf = transformix(t0f, imf);

% create masks
opts.mMask = uint8(sum(imm, 3) > 0);
opts.fMask = uint8(sum(imf, 3) > 0);

% remove some background noise in the mask
se = strel('disk', 1);
opts.mMask = imerode(opts.mMask, se);
opts.fMask = imerode(opts.fMask, se);

% dilate mask to cover some background
se = strel('disk', 10);
opts.mMask = imdilate(opts.mMask, se);
opts.fMask = imdilate(opts.fMask, se);

% register slices
[tm, immreg, iterinfo] = elastix(regParam, imf, imm, opts);

if (DEBUG)
    subplot(2, 1, 1)
    hold off
    imshowpair(imf, imm)
    subplot(2, 1, 2)
    hold off
    imshowpair(imf, immreg)
end
    

% apply diffusion
tm.TransformParameters ...
    = tm.TransformParameters * 2 * opts.DiffusionCoefficient;

% add diffused transform to the list of accumulated transforms
tm.InitialTransformParametersFileName = t0m;

end

% process_intermediate_slices()
%
%   All slices of the histology volume except the first and last have
%   slices on both sides. This function computes the difussion registration
%   of a slice to its two adjacent slices.
%
%   *M refers to the moving slice, i.e. the first or last histology slice.
%   *FA, *FB refer to the two fixed adjacent slices.
%
%   FILEM, FILEFA, FILEFB are the path and filename to the histology
%   images.
%
%   T0M, T0FA, T0FB are the nested (accumulated) transforms to apply to
%   each image before registering them.
%
%   REGPARAM is the struct with the registration parameters for elastix.
%
%   OPTS is a struct with optional algorithm parameters.
function tm = process_intermediate_slices(filefa, filem, filefb, t0fa, t0m, t0fb, regParam, opts)

DEBUG = 0;

% load images
imm = imread(filem);
imfa = imread(filefa);
imfb = imread(filefb);

% preprocess histograms
[~, imfa] = histology_preprocessing(imm, imfa);
[imm, imfb] = histology_preprocessing(imm, imfb);

% apply accumulated initial transform (make sure that added voxels are
% black, so that they blend in with the background)
t0m.DefaultPixelValue = 0;
t0fa.DefaultPixelValue = 0;
t0fb.DefaultPixelValue = 0;
imm = transformix(t0m, imm);
imfa = transformix(t0fa, imfa);
imfb = transformix(t0fb, imfb);

% create masks
opts.mMask = uint8(sum(imm, 3) > 0);
fMaska = uint8(sum(imfa, 3) > 0);
fMaskb = uint8(sum(imfb, 3) > 0);

% remove some background noise in the mask
se = strel('disk', 1);
opts.mMask = imerode(opts.mMask, se);
fMaska = imerode(fMaska, se);
fMaskb = imerode(fMaskb, se);

% dilate mask to cover some background
se = strel('disk', 10);
opts.mMask = imdilate(opts.mMask, se);
fMaska = imdilate(fMaska, se);
fMaskb = imdilate(fMaskb, se);

% register slices
opts.fMask = fMaska;
[tma, immrega, iterinfoa] = elastix(regParam, imfa, imm, opts);
opts.fMask = fMaskb;
[tmb, immregb, iterinfob] = elastix(regParam, imfb, imm, opts);

if (DEBUG)
    subplot(2, 2, 1)
    hold off
    imshowpair(imfa, imm)
    subplot(2, 2, 3)
    hold off
    imshowpair(imfa, immrega)
    subplot(2, 2, 2)
    hold off
    imshowpair(imfb, imm)
    subplot(2, 2, 4)
    hold off
    imshowpair(imfb, immregb)
end

% apply diffusion
tm = tma;
tm.TransformParameters ...
    = (tma.TransformParameters + tmb.TransformParameters) ...
    * opts.DiffusionCoefficient;

% add diffused transform to the list of accumulated transforms
tm.InitialTransformParametersFileName = t0m;

end
