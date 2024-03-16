function [ ntsStruct ] = parseNotes( nts )
% INFORMATION & USAGE %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Called by readARDF to parse Asylum Research Notes into note structure
% Use str2num to convert strings to numbers when and where needed
% Written by Matt Poss
% 2018-11-07
% Uses pointers extensively
siz = size(nts);
idx = 1;
pntTitleStart = 1;
pntTitleEnd = 1;
pntFirstColon = 1;
pntDataStart = 1;
pntDataEnd = 1;
found = 0;
ntsStruct = struct;
while idx <= siz(2)
	
    %if first colon not found, find the first colon
    if (nts(idx) == ':') && (found == 0)
        pntFirstColon = idx;
        pntTitleEnd = idx - 1;
        if nts(idx + 1) == ' '
            pntDataStart = idx + 2;
        else
            pntDataStart = idx + 1;
        end
        found = 1;
    end
    
    %find the end
    if nts(idx) == 13
        pntDataEnd = idx - 1;
        
        %Create title string
        tempStr = sprintf('%c', nts(pntTitleStart : pntTitleEnd));
        
		% Remove blanks from title name
		tempStr = tempStr(~isspace(tempStr));
		% Remove periods from title name
		tempStr = tempStr('.'~=tempStr);
		% Determine title size
		titleSize = size(tempStr);
		
        %Create array for data
        dataSize = pntDataEnd - pntDataStart + 1;
        tempAr = blanks(dataSize);
        %Copy data to new array
		tempAr = nts(pntDataStart:pntDataEnd);
        
        %Add note to note structure
        if found == 1
            
            % Catch numeric first letters
            if isnan( str2double(tempStr(1)) )
                ntsStruct.(tempStr) = tempAr;
            else
                tempStr = ['n' tempStr];
                ntsStruct.(tempStr) = tempAr;
            end
        end
            
        %Reset pointers
        pntTitleStart = idx + 1;
        found = 0;
        
    end
 
    idx = idx + 1;
	
    
end
% Returns ntsStruct
end

