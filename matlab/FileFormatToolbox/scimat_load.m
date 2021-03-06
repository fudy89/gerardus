function scimat = scimat_load(file)
% SCIMAT_LOAD  Load an image into a SCIMAT struct from a Matlab, MetaImage,
% Carl Zeiss LSM or Hamamatsu VMU file.
%
% SCIMAT = scimat_load(FILE)
%
%   This function loads the image and metainformation into a scimat struct.
%   If necessary, it swaps rows and columns to follow Matlab's convention
%   that (rows, columns) <=> (y, x).
%
%   FILE is a string with the path and name of the .mat, .mha, .lsm or .vmu
%   file that contains the 2D or 3D image:
%
%     .mat: Matlab binary file with a "scirunnrrd" struct (see below for
%           details).
%
%     .mha: MetaImage file (developed for the ITK and VTK libraries). The
%          .mha file can be pure text, containing only the image metadata,
%          and a path to the file with the actual binary image data, or it
%          can contain both text metadata and binary image within the same
%          file.
%
%     .lsm: Carl Zeiss microscopy image format. Binary file.
%
%     .vmu: Hamamatsu Uncompressed Virtual Microscope Specimen. Text file
%           containing only the image metadata, and a path to the file with
%           the actual binary image data.
%
%   SCIMAT is the struct with the image data and metainformation (see "help
%   scimat" for details).
%
% See also: scimat, scimat_save.

% Author: Ramon Casero <rcasero@gmail.com>
% Copyright © 2010-2015 University of Oxford
% Version: 0.4.5
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
narginchk(1, 1);
nargoutchk(0, 1);

% extract extension of filename in lower case
[pathstr, ~, ext] = fileparts(file);
ext = lower(ext);

switch lower(ext)
    
    case '.mat' % Matlab file in Seg3D scirunnrrd format
        
        % load data
        scimat = load(file);
        
        % rename SCIMAT volume for convenience
        scimat = scimat.scirunnrrd;
        
        % remove dummy dimension in old files created with Seg3D 1.x
        scimat = scimat_squeeze(scimat);
        
        % correct x-,y-coordinates
        scimat = scimat_seg3d2matlab(scimat);
        
        % remove extra metainformation that is not used
        scimat = rmfield(scimat, 'property');
        scimat.axis = rmfield(scimat.axis, ...
            {'max', 'center', 'label', 'unit'});
        
        % empty rotation matrix
        scimat.rotmat = [];
        
    case {'.mha', '.mhd'} % MetaImage file
        
        % open file to read
        fid=fopen(file, 'r');
        if (fid<=0)
            error(['Cannot open file: ' file])
        end
        
        % default values for the text header
        N = [];
        sz = [];
        data_type = [];
        offset = [];
        res = [];
        msb = [];
        rawfile = [];
        
        % process text header, and stop if we get to the raw data
        while 1
            % read text header line
            tline = fgetl(fid);
            
            % if end of text header stop reading
            % Warning: this only works if the first voxel=0. Otherwise, we
            % would read some voxels as part of a header line. To avoid it,
            % we now break after finding ElementDataFile
            if (tline(1) == 0), break, end
            
            % pointer to current position in header
            eoh = ftell(fid);
            
            % parse text header line
            
            % find location of "=" sign
            idx = strfind(tline, '=');
            if isempty(idx), break, end
            
            switch getlabel(tline, idx)
                case 'ndims'
                    N = getnumval(tline, idx);
                case 'dimsize'
                    sz = getnumval(tline, idx);
                case 'elementtype'
                    switch lower(strtrim(tline(idx+1:end)))
                        case 'met_uchar'
                            data_type = 'uint8';
                        case 'met_char'
                            data_type = 'int8';
                        case 'met_ushort'
                            data_type = 'uint16';
                        case 'met_short'
                            data_type = 'int16';
                        case 'met_uint'
                            data_type = 'uint32';
                        case 'met_int'
                            data_type = 'int32';
                        case 'met_float'
                            data_type = 'single';
                        case 'met_double'
                            data_type = 'double';
                        otherwise
                            error('Unrecognized ElementType')
                    end
                case 'offset'
                    offset = getnumval(tline, idx);
                case 'elementspacing'
                    res = getnumval(tline, idx);
                case 'elementbyteordermsb'
                    msb = strcmpi(strtrim(tline(idx+1:end)), 'true');
                case 'elementdatafile'
                    rawfile = strtrim(tline(idx+1:end));
                    break;
                case 'compresseddata'
                    if strcmpi(strtrim(tline(idx+1:end)), 'true')
                        error('Cannot read compressed MHA data')
                    end
                otherwise
                    warning(['Unrecognized line: ' tline])
            end
            
        end
        
        % the raw data can be after the text header, or in a separate file. If
        % there's a pointer to an external file, we assume that the data is
        % there
        if (isempty(rawfile))
            error('No pointer to data in header')
        elseif (strcmp(rawfile, 'LOCAL')) % data after text header
            % do nothing
        else % data in external file
            % close mha file
            fclose(fid);
            
            % open raw file to read
            fid=fopen([pathstr filesep rawfile], 'r');
            if (fid<=0)
                error(['Cannot open file: ' pathstr filesep rawfile])
            end
        end
        
        % read all the raw data into a vector, because we cannot read it
        % into a 3D volume
        scimat.data = fread(fid, prod(sz), [data_type '=>' data_type]);
        
        % reshape the data to create the data volume
        scimat.data = reshape(scimat.data, sz);
        
        % permute the X and Y coordinates
        scimat.data = permute(scimat.data, [2 1 3]);
        
        % close file
        fclose(fid);
        
        % check that we have enough data to create the output struct
        if (isempty(sz) || isempty(res) || isempty(offset))
            error('Incomplete header in .mha file')
        end
        
        % create output struct (we have read sz, res, etc in x, y, z order)
        for I = 1:N
            scimat.axis(I).size = sz(I);
            scimat.axis(I).spacing = res(I);
            scimat.axis(I).min = offset(I) - res(I)/2;
        end
        scimat.axis = scimat.axis';
        
        % now we need to permute the axis so that we have [row, col,
        % slice]-> [y, x, z]
        scimat.axis([1 2]) = scimat.axis([2 1]);
        
    case '.lsm' % Carl Zeiss LSM format
        
        % read TIFF file
        warning('off', 'tiffread2:LookUp')
        stack = tiffread(file);
        warning('on', 'tiffread2:LookUp')
        
        % convert to sci format
        scimat = scimat_tiff2scimat(stack);
        
    case '.vmu' % Hamamatsu miscroscope format (Uncompressed Virtual Microscope Specimen)
        
        % init resolution and size vectors
        rawfile = '';
        res = [0 0 NaN];
        sz = [0 0 1];
        offset = [0 0 0];
        bpp = [];
        pixelorder = '';
        
        % open header file to read
        fid = fopen(file, 'r');
        if (fid == -1)
            error('Gerardus:CannotReadFile', ...
                ['Cannot open file for reading:\n' file])
        end
        
        % read metainfo from header
        tline = fgetl(fid);
        while ischar(tline)
            
            % find the '=' in the line
            idx = strfind(tline, '=');
            if (isempty(idx))
                % if this line has no label=value format, skip to next
            end
            
            % split line into label and value
            label = tline(1:idx-1);
            value = tline(idx+1:end);
            
            switch label
                
                case 'ImageFile(0)'
                    
                    % name of file with the image data
                    rawfile = value;

                case 'PixelWidth'
                    
                    sz(2) = str2double(value);
                
                case 'PixelHeight'
                    
                    sz(1) = str2double(value);
                
                case 'PhysicalWidth'
                    
                    % units are nm
                    res(2) = str2double(value) * 1e-9;
                
                case 'PhysicalHeight'
                    
                    % units are nm
                    res(1) = str2double(value) * 1e-9;
                
                case 'XOffsetFromSlideCentre'
                    
                    offset(1) = str2double(value) * 1e-9;
                
                case 'YOffsetFromSlideCentre'
                    
                    offset(2) = str2double(value) * 1e-9;
                    
                case 'BitsPerPixel'
                    
                    bpp = str2double(value);
                    
                case 'PixelOrder'
                    
                    pixelorder = value;
                    
            end
            
            % read next line
            tline = fgetl(fid);
            
        end
        fclose(fid);
        
        % at this point in the code, res, sz -> (rows, cols, slices)
        
        % compute pixel size from the total image size
        res(1) = res(1) / sz(1);
        res(2) = res(2) / sz(2);
        
        % check that the image is RGB
        if (~strcmpi(pixelorder, 'RGB'))
            error('Microscopy image is not RGB')
        else
            numchannels = 3;
        end

        % check that we know the number of bits per pixel
        if (isempty(bpp))
            warning('File does not provide field BitsPerPixel. Assuming 3 bytes per pixel')
            bpp = 24;
        end
        
        % number of bytes per channel per pixel
        numbyte = bpp / 8 / numchannels;
        
        % translate number of bits per pixel to Matlab data type
        switch numbyte
            case 1
                pixeltype = 'uint8';
            otherwise
                error('Unknown data type. File does not contain one byte per channel per pixel')
        end
        
        
        % read image data to an array with the appropriate pixel type
        % (note: '*uint8' is shorthand for 'uint8=>uint8')
        [pathstr, ~, ~] = fileparts(file);
        fid = fopen([pathstr filesep rawfile], 'r');
        if (fid == -1)
            error('Gerardus:CannotReadFile', ...
                ['Cannot open file for reading:\n' file])
        end
        im = fread(fid, numchannels * sz(1) * sz(2), ['*' pixeltype]);
        fclose(fid);
        
        % reshape image array to produce an image R*C*channels that can be
        % visualized with imagesc()
        im = reshape(im, [numchannels sz(2) sz(1)]);
        im = permute(im, [3 2 1]);
        
        % add a dummy dimension, so that it is clear that we don't have 3
        % slices instead of 3 channels
        im = reshape(im, [size(im, 1) size(im, 2) 1 size(im, 3)]);
        
        % create SCI MAT struct
        scimat = scimat_im2scimat(im, res, offset);
        
    otherwise
        
        error('Invalid file extension')
end

end

function s = getlabel(s, idx)
s = lower(strtrim(s(1:idx-1)));
end
function n = getnumval(s, idx)
n = str2num(s(idx+1:end));
end
