function [G] = getARDFdata(FN, getPoint, getLine, trace, fileStruct)
% INFORMATION & USAGE %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% getARDFdata: Loads either a single force curve or a line of force curves 
%                from binary Asylum Research Data File (ARDF) into a Matlab structure D.
%              Reading directly from the ARDF file eliminates the need to create copies
%                of these extremely large files.
%              Often used with readARDF(), which loads images, notes, and other information
%                from the ARDF file into a Matlab structure.
%              Pads end of force curve vectors with zeros if curves are of different length.
%
% Usage: D = getARDFdata('Foo.ardf') reads from binary ARDF file Foo.ardf.
% Written by Matt Poss
% 2018-11-07
% INPUT ARGUMENTS %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% FN:         File name (eg. 'Foo.ardf')
% getLine:    Line number, starting at 0 (eg. 0, 1, ... , 255)
% getPoint:   Point # starting at 0. -1 returns entire line.
% trace:      1: trace, 0: retrace.
% fileStruct: The structure returned by readARDF(). Providing this structure is optional.
%             Proving this structure improves file read times for repetitive reads.
% If only trace or retrace exist (not both), function will return the existing data 
% (trace or retrace) regardless of the provided 'trace' argument
% CRC-32 used.
% Data used for checksum is entire entry minus the checksum.
hasFileStruct = 1;
if nargin < 5
	hasFileStruct = 0;
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Determine if imported MATLAB file exists
% Remove last 4 letters from FN
FNbase = FN(1:end-4);
FNmat = [FN 'mat'];
% Open file for reading
fid = fopen(FN,'r');
% Determine if file structure exists
if hasFileStruct
	% Use provided file structure
	F = fileStruct;
elseif exist(FNmat, 'file') == 2
    % Open Matlab file for reading
    D = load(FNmat,'D');
    F = D.FileStructure;
    
else
    
    % =======================================
    % ARDF: Asylum Research Data File
    % Read file header
    % =======================================
    % Read file header & verify header type
    [dumCRC, dumSize, lastType, dumMisc] = local_readARDFpointer(fid,0);
    local_checkType(lastType, 'ARDF', fid);
    % =======================================
    % FTOC: File Table of Contents
    % =======================================
    % Read FTOC table
    F.ftoc = local_readTOC(fid, -1, 'FTOC');
    % =======================================
    % VOLM: Force Curve Data
    % =======================================
    % Determine number of volumes
    F.numbVolm = size(F.ftoc.pntVolm,1);
    % Initialize data arrays
    D.channelList = [];
    
    % Import header data and pointers for each volume
    for n = 1:F.numbVolm
        % Determine dynamic volume structure name
        volmN = ['volm' num2str(n)];
        % * * * * * * * * * * *
        % VOLM Header
        % Read all VOLM entries
        F.(volmN) = local_readTOC(fid, F.ftoc.pntVolm(n), 'VOLM');
        % * * * * * * * * * * *
        % VOLM-TTOC
        % Read all VOLM-TTOC entries
        loc_VOLM_TTOC = F.ftoc.pntVolm(n) + F.(volmN).sizeTable;
        F.(volmN).ttoc = local_readTOC(fid, loc_VOLM_TTOC, 'TTOC');
        % There do not appear to be any volume notes.
        % * * * * * * * * * * *
        % VOLM-VDEF
        % Read VDEF entry
        loc_VDEF_IMAG = F.ftoc.pntVolm(n) + F.(volmN).sizeTable + F.(volmN).ttoc.sizeTable;
        F.(volmN).vdef = local_readDEF(fid, loc_VDEF_IMAG, 'VDEF');
        % * * * * * * * * * * *
        % VOLM-VCHN & VOLM-XDEF
        % Initialize local arrays
        F.(volmN).vchn = [];
        F.(volmN).xdef = [];
        % We unfortunately don't know how many VCHN entries to expect
        done = 0;
        while done == 0
            % Read header
            [dumCRC, lastSize, lastType, dumMisc] = local_readARDFpointer(fid,-1);
            % Read data differently depending on data type
            switch lastType
                case 'VCHN'
                    % Read 32 bytes of text
                    textSize = 32;
                    theChannel = transpose( fread(fid, textSize, '*char') );
                    % Append to channelList
                    F.(volmN).vchn = [F.(volmN).vchn; theChannel];
                    % Read 32 dummy bytes
                    remainingSize = lastSize - 16 - textSize;
                    dum = fread(fid, remainingSize, '*char');
                case 'XDEF'
                    % Read additional header parameters
                    dum = fread(fid, 1, 'uint32');
                    F.(volmN).xdef.sizeTable = fread(fid, 1, 'uint32');
                    % Read text
                    F.(volmN).xdef.text = transpose( fread(fid, F.(volmN).xdef.sizeTable, '*char') );
                    % Read zero values
                    dum = fread(fid, lastSize - 16 - 8 - F.(volmN).xdef.sizeTable, '*char');
                    % Exit while loop
                    done = 1;
                otherwise
                    error(['ERROR: ' typeEntry ' not recognized!']);
            end % end switch type
        end % end while loop
        % Write channel list data to structure
        D.channelList = cat(3, D.channelList, F.(volmN).vchn);
        % * * * * * * * * * * *
        % VOLM-VTOC & VOLM-VOFF
        % Read Entire VTOC/VOFF Table
        F.(volmN).idx = local_readTOC(fid, -1, 'VTOC');
        % * * * * * * * * * * *
        % VOLM-MLOV
        % Verify that we have readed the end VOLM header, MLOV
        [dumCRC, lastSize, lastType, dumMisc] = local_readARDFpointer(fid,-1);
        local_checkType(lastType, 'MLOV', fid);
        % * * * * * * * * * * *
        % VOLM-VSET
        % Read first and last VSET point to get trace/retrace, up/down information
        % Alternatively every VSET can be read, but this takes more time, space
        % for r = 1:F.(volmN).vdef.lines
        for r = [1 F.(volmN).vdef.lines]
            % Determine dynamic field name
            vsetN = ['vset' num2str(r)];
            % Determine VSET address
            loc = F.(volmN).idx.linPointer(r);
			
			% If the data exists
			if loc ~= 0
				% Record VSET information
				F.(volmN).line.(vsetN) = local_readVSET(fid, loc);
				% Record Scan Up/Down information
				if F.(volmN).line.(vsetN).line ~= (r - 1)
					F.(volmN).scanDown = 1;
				else
					F.(volmN).scanDown = 0;
				end
				% Record Trace/Retrace Information
				if F.(volmN).line.(vsetN).point == 0
					F.(volmN).trace = 1;
				else
					F.(volmN).trace = 0;
				end
			end
        end % end for get point, line information
    end % end read all VOLM information
end % END IF .MAT FILE DOES NOT EXIST
% =======================================
% Get Desired Data
% =======================================
% Trace/retrace selection
% If we have two volumes, choose the desired one
if F.numbVolm > 1
    if trace == F.volm1.trace
        getVolm = 'volm1';
    else
        getVolm = 'volm2';
    end
else
    getVolm = 'volm1';
end
% Get number of points
numbPoints = F.(getVolm).vdef.points;
% If ScanDown, create an adjusted line index variable
numbLines = F.(getVolm).vdef.lines;
if F.(getVolm).scanDown == 1
    adjLine = numbLines - getLine - 1;
else
    adjLine = getLine;
end
% Determine the number of data channels
%numbChannels = size(D.channelList, 1);
numbChannels = size(F.volm1.vchn,1);
% Get the desired data
% Get location of first VSET in line
locLine = F.(getVolm).idx.linPointer(adjLine+1);
% If data exists
if locLine ~= 0
	% Navigate to the desired location
	fseek(fid, locLine, 'bof');
	% Initialize data arrays
	G.numbForce = [];
	G.numbLine = [];
	G.numbPoint = [];
	G.locPrev = [];
	G.locNext = [];
	G.name = [];
	G.y = [];
	G.pnt0 = [];
	G.pnt1 = [];
	G.pnt2 = [];
	% Read in the entire line
	for n = 1:numbPoints
		
		% Read VSET info
		vset = local_readVSET(fid, -1);
		
		% Write VSET info to arrays
		G.numbForce = [G.numbForce; vset.force];
		G.numbLine = [G.numbLine; vset.line];
		G.numbPoint = [G.numbPoint; vset.point];
		G.locPrev = [G.locPrev; vset.prev];
		G.locNext = [G.locNext; vset.next];
		
		% Read & write VNAM info
		vnam = local_readVNAM(fid, -1);
		G.name = [G.name; vnam.name];
		
		% Clear data matrix
		theData = [];
		
		% Read VDAT info
		for r = 1:numbChannels
			vdat = local_readVDAT(fid, -1);
			theData = [theData vdat.data];
		end
		
		% Read XDAT if it exists
		% Not sure what data is stored in XDAT
		local_readXDAT(fid, -1);
		
		% Concatenate data
		% If not the same number of rows, pad smaller data with zeros
		rowsGy  = size(G.y, 1);
		rowsDat = size(theData, 1);
		if (rowsGy ~= rowsDat) && (n ~= 1)
			
			% Determine max number of rows
			maxRows = max([ rowsGy rowsDat ]);
			
			% If G.y less than max rows, pad it
			if rowsGy < maxRows
				
				% Get size of Gy
				sizeGy = size(G.y);
				
				% Set new number of rows
				sizeGy(1) = maxRows;
				
				% Copy old G.y
				oldGy = G.y;
				
				% Create new array
				G.y = zeros(sizeGy);
				
				% Copy depending on 2D or 3D size of array
				if max( size( sizeGy ) ) > 2
					G.y(1:rowsGy,:,:) = oldGy;
				else
					G.y(1:rowsGy,:) = oldGy;
				end
				
			% If theData less than max rows, pad it
			else
				
				% Get size of theData
				sizeDat = size(theData);
				
				% Set new number of rows
				sizeDat(1) = maxRows;
				
				% Copy old theData
				oldDat = theData;
				
				% Create new array
				theData = zeros(sizeDat);
				
				% Copy old to new
				theData(1:rowsDat,:) = oldDat;
				
			end % end if need to pad array
			
		end % end if not equivalent sizes
		
		% Do a straight concatination
		G.y = cat(3, G.y, theData);
		
		% Write VDAT pointers only for the final channel read
		G.pnt0 = [G.pnt0; vdat.pnt0];    % Pointers, presumably
		G.pnt1 = [G.pnt1; vdat.pnt1];
		G.pnt2 = [G.pnt2; vdat.pnt2];
		
	end % end read line
	
	% Flip each array if retrace data
	if G.numbPoint(1) ~= 0
		
		G.numbForce = flip(G.numbForce,1);
		G.numbLine  = flip(G.numbLine ,1);
		G.numbPoint = flip(G.numbPoint,1);
		G.locPrev   = flip(G.locPrev  ,1);
		G.locNext   = flip(G.locNext  ,1);
		G.name      = flip(G.name     ,1);
		G.y         = flip(G.y        ,3); % Note 3rd dimension
		G.pnt0      = flip(G.pnt0     ,1);
		G.pnt1      = flip(G.pnt1     ,1);
		G.pnt2      = flip(G.pnt2     ,1);
	
	end % end flip if retrace data
	
	% If only a point desired, return only the point
	if getPoint ~= -1
		% Adjust index
		getPoint = getPoint + 1;
		
		% Get data
		G.numbForce = G.numbForce(getPoint);
		G.numbLine = G.numbLine(getPoint);
		G.numbPoint = G.numbPoint(getPoint);
		G.locPrev = G.locPrev(getPoint);
		G.locNext = G.locNext(getPoint);
		G.name = G.name(getPoint,:);
		G.y = G.y(:,:,getPoint);
		G.pnt0 = G.pnt0(getPoint);
		G.pnt1 = G.pnt1(getPoint);
		G.pnt2 = G.pnt2(getPoint);
	end
else
	G = [];
end % end if data exists
	
% * * * * * * * * * * * * *
fclose(fid);
end % end main function
% @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
% @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
%
% Local Functions
%
% @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
% @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
% =======================================
% readTOC Function
% =======================================
function [toc] = local_readTOC(fid, address, type)
	
    % Define null pointer title
    nullCase = char([0 0 0 0]);
    
    if address ~= -1
        % Navigate to address
        fseek(fid, address, 'bof'); 
    end
    
    % Read TOC header, verify if correct type
    [dumCRC, lastSize, lastType, dumMisc] = local_readARDFpointer(fid,-1);
    local_checkType(lastType, type, fid);
    
    % Read remaining TOC header (assumes 32 byte header)
    toc.sizeTable = fread(fid,1,'uint64');
    toc.numbEntry = fread(fid,1,'uint32');
    toc.sizeEntry = fread(fid,1,'uint32');
    
    % Initialize pointer arrays
    switch toc.sizeEntry
        case 24
            % FTOC, IMAG, VOLM
            toc.pntImag = [];
            toc.pntVolm = [];
            toc.pntNext = [];
            toc.pntNset = [];
            toc.pntThmb = [];
        case 32
            % TTOC
            toc.idxText = [];
            toc.pntText = [];
        case 40 
            % VOFF
            toc.pntCounter = [];
            toc.linCounter = [];
            toc.linPointer = [];
        otherwise
            % IDAT
            toc.data = [];
            sizeRead = (toc.sizeEntry - 16) / 4;
    end % end switch
    
    % Initialize parameters for while loop
    done = 0;
    numbRead = 1;
    % Read TOC entries
    while (done == 0) && (numbRead <= toc.numbEntry)
        % Read entry header
        [dumCRC, dumSize, typeEntry, dumMisc] = local_readARDFpointer(fid,-1);
        % Read remainder of entry
        switch toc.sizeEntry
            case 24
                % FTOC, IMAG, VOLM
                lastPointer = fread(fid,1,'uint64');
            case 32
                % TTOC
                lastIndex = fread(fid,1,'uint64');
                lastPointer = fread(fid,1,'uint64');
            case 40
                % VOFF
                lastPntCount = fread(fid,1,'uint32');
                lastLinCount = fread(fid,1,'uint32');
                dum = fread(fid,1,'uint64');
                lastLinPoint = fread(fid,1,'uint64');
            otherwise
                % IDAT
                lastData = fread(fid, sizeRead, 'single');
        end % end switch
        % Record pointer depending on type of entry
        switch typeEntry
            case 'IMAG'
                toc.pntImag = [toc.pntImag; lastPointer];
            case 'VOLM'
                toc.pntVolm = [toc.pntVolm; lastPointer];
            case 'NEXT'
                toc.pntNext = [toc.pntNext; lastPointer];
            case 'NSET'
                toc.pntNset = [toc.pntNset; lastPointer];
            case 'THMB'
                toc.pntThmb = [toc.pntThmb; lastPointer];
            case 'TOFF'
                toc.idxText = [toc.idxText; lastIndex];
                toc.pntText = [toc.pntText; lastPointer];
            case 'IDAT'
                toc.data = [toc.data lastData];
            case 'VOFF'
                toc.pntCounter = [toc.pntCounter; lastPntCount];
                toc.linCounter = [toc.linCounter; lastLinCount];
                toc.linPointer = [toc.linPointer; lastLinPoint];
            case nullCase
                switch lastType
                    case 'IBOX'
                        toc.data = [toc.data lastData];
                    case 'VTOC'
                        toc.pntCounter = [toc.pntCounter; lastPntCount];
                        toc.linCounter = [toc.linCounter; lastLinCount];
                        toc.linPointer = [toc.linPointer; lastLinPoint];
                    otherwise
                        done = 1;
                end % end switch
            otherwise
                error(['ERROR: ' typeEntry ' not recognized!']);
        end % end switch
        
        % Increment entry counter
        numbRead = numbRead + 1;
    end % end while loop
end % end local_readTOC()
% =======================================
% readVSET Function
% =======================================
function [vset] = local_readVSET(fid, address)
    
    if address ~= -1
        % Navigate to address
        fseek(fid, address, 'bof'); 
    end
    
    % Read header, verify if correct type
    [dumCRC, lastSize, lastType, dumMisc] = local_readARDFpointer(fid,-1);
    local_checkType(lastType, 'VSET', fid);
    
	% Read VSET data
    vset.force = fread(fid, 1, 'uint32');
    vset.line = fread(fid, 1, 'uint32');
    vset.point = fread(fid, 1, 'uint32');
    dum = fread(fid, 1, 'uint32');
    vset.prev = fread(fid, 1, 'uint64');
    vset.next = fread(fid, 1, 'uint64');
    
end % end local_readVSET()
% =======================================
% readVNAM Function
% =======================================
function [vnam] = local_readVNAM(fid, address)
    if address ~= -1
        % Navigate to address
        fseek(fid, address, 'bof'); 
    end
    
    % Read header, verify if correct type
    [dumCRC, lastSize, lastType, dumMisc] = local_readARDFpointer(fid,-1);
    local_checkType(lastType, 'VNAM', fid);
    
    % Read data
    vnam.force = fread(fid, 1, 'uint32');
    vnam.line = fread(fid, 1, 'uint32');
    vnam.point = fread(fid, 1, 'uint32');
    vnam.sizeText = fread(fid, 1, 'uint32');
    vnam.name = transpose( fread(fid, vnam.sizeText, '*char') );
    
    % Determine remaining size
    remainingSize = lastSize - 16 - vnam.sizeText - 16;
    
    % Read remaining zeros to dummy variable
    dum = fread(fid, remainingSize, '*char');
    
end % end local_readVNAM(fid, address)
% =======================================
% readVDAT Function
% =======================================
function [vdat] = local_readVDAT(fid, address)
    
    if address ~= -1
        % Navigate to address
        fseek(fid, address, 'bof'); 
    end
    
    % Read header, verify if correct type
    [dumCRC, lastSize, lastType, dumMisc] = local_readARDFpointer(fid,-1);
    local_checkType(lastType, 'VDAT', fid);
    
    % Read data
    vdat.force = fread(fid, 1, 'uint32');
    vdat.line = fread(fid, 1, 'uint32');
    vdat.point = fread(fid, 1, 'uint32');
    vdat.sizeData = fread(fid, 1, 'uint32'); % number of floats
    
    vdat.forceType = fread(fid, 1, 'uint32');
    vdat.pnt0 = fread(fid, 1, 'uint32');    % Pointers, presumably
    vdat.pnt1 = fread(fid, 1, 'uint32');
    vdat.pnt2 = fread(fid, 1, 'uint32');
    dum = fread(fid, 2, 'uint32');
    
    % Read data
    vdat.data = fread(fid, vdat.sizeData, 'single');
    
end % end local_readVDAT
% =======================================
% readDEF Function
% =======================================
function [def] = local_readDEF(fid, address, type)
    
    if address ~= -1
        % Navigate to address
        fseek(fid, address, 'bof'); 
    end
    
    % Read DEF header, verify if correct type
    [dumCRC, sizeDEF, typeDEF, dumMisc] = local_readARDFpointer(fid,-1);
    local_checkType(typeDEF, type, fid);
	% Read points & lines
	def.points = fread(fid, 1, 'uint32');
	def.lines = fread(fid, 1, 'uint32');
	
    % Set bytes to skip
    switch typeDEF
        case 'IDEF'
            skip = 96;
        case 'VDEF'
            skip = 144;
    end % end switch
    
	% Read some bytes as dummy bytes
	dum = fread(fid, skip, '*char');
	
	% Read 32 bytes as text
    sizeText = 32;
	def.imageTitle = transpose( fread(fid, sizeText, '*char') );
    
	% Read remaining bytes as dummy bytes
    sizeHead = 16;
	remainingSize = sizeDEF - 8 - skip - sizeHead - sizeText;
	dum = fread(fid, remainingSize, '*char');
end % end local_readDEF()
% =======================================
% readXDAT Function
% =======================================
function [def] = local_readXDAT(fid, address)
	if address ~= -1
		% Navigate to address
		fseek(fid, address, 'bof'); 
	end
	
	% Read header
    [dumCRC, lastSize, lastType, dumMisc] = local_readARDFpointer(fid,-1);
	
	% Verify if header correct type
	if (~strcmp(lastType, 'XDAT')) && (~strcmp(lastType, 'VSET'))
        error(['ERROR: No XDAT or VSET here!  Found: ' found '  Location:' num2str( ftell(fid)-16 )]);
    end
	
	% Choose action depending on header type
	switch lastType
	
		% If XDAT
		case 'XDAT'
			
			% Determine distance to step forward
			stepDist = lastSize - 16;
			
			% Step forward that distance
			fseek(fid, stepDist, 'cof'); 
			
		% If VSET, step back 16 bytes
		case 'VSET'
		
			% Step back 16 bytes (the size of ARDF header)
			fseek(fid, -16, 'cof'); 
		
	end % end switch lastType
	
end % end local_readXDAT()
% =======================================
% readARDFpointer Function
%
% Reads ARDF pointer. All pointers have similar 16 byte header.
% =======================================
function [ checkCRC32, sizeBytes, typePnt, miscNum ] = local_readARDFpointer( fid, address )
% Each pointer/header is 16 bytes
if address ~= -1
	% Navigate to address
	fseek(fid,address,'bof'); 
end
% Initialize typePnt
typePnt = zeros(1,4);
% Read pointer
checkCRC32 = fread(fid,1,'uint32');			% Read CRC-32 checksum
sizeBytes = fread(fid,1,'uint32');			% Read byte size of section
typePnt = transpose( fread(fid,4,'*char') );% Read 4-character pointer type
miscNum = fread(fid,1,'uint32');			% Read misc number
end % end local_local_readARDFpointer
% =======================================
% checkType Function
% 
% Verifies that pointer type is the expected type.
% =======================================
function [] = local_checkType(found, test, fid)
    if ~strcmp(found, test)
        error(['ERROR: No ' test ' here!  Found: ' found '  Location:' num2str( ftell(fid)-16 )]);
    end
end % end local_checkType

