function [CIR_cell, hcoef, info] = gen_channelcoeff(sysPar,carrier,Layout,Chan,RFI);
%gen_channelcoeff Generate channel impulse response for all BS-UE links
% which in line with configurated NR signal system.
%
% Description:
% Output: CIR_cell = cell(nRr, nTr);  dim of CIR{1,1}: nDelay * nTx * nRx * nslot
% Note:
% hcoef contains the detailed multipath information. The CIR is generated by
% frequency-domain modulation, and thus the real time delay and antenna
% phase offset would be retained.
%
% Developer: Jia. Institution: PML. Date: 2022/01/10

nfft = carrier.Nfft;
del_f = carrier.SubcarrierSpacing * 1000;
nRr = sysPar.nRr;
nTr = sysPar.nTr;
%% ======Generate channel coefficient====%
[hcoef, info] = get_channelcoeff( Chan, Layout);
[~, nRx , nTx, nslot] = size(hcoef(1, 1).H);
CIR_cell = cell(nRr, nTr);
if RFI.Ind_AntPhaseOffset == true
    Ang_Loc = gen_localAngle(info, sysPar, nslot);
    get_interpPhaseoffset(RFI);
end
%% ======Generate channel impulse response====%
for iRr = 1 : nRr
    for iTr = 1 : nTr
        if sysPar.IndUplink
            PathCoeff = permute( hcoef(iRr, iTr).H, [1 3 2 4]);
            %nP * nTx * nRx * nRSslot
            PathDelay = hcoef(iRr, iTr).timedelay;
        else
            PathCoeff = permute( hcoef(iTr, iRr).H, [1 3 2 4]);
            %nP * nTx * nRx * nRSslot
            PathDelay = hcoef(iTr, iRr).timedelay;
        end
        if RFI.Ind_ApproxiCIR == false
            PathDelay = permute(PathDelay,[1 3 4 2]); %nP * nTx * nRx * nRSslot
            nF = ( -nfft /2: nfft /2-1).';
            nF = permute(nF,[2 3 4 5 1]);
            CFRpath_phase_delay = PathDelay .* nF * nfft * del_f *2 *pi / nfft;
            %nP * nTx * nRx * nRSslot * nFFT
            hfcoe_temp = abs( PathCoeff ) .* exp( 1i * (angle( PathCoeff )...
                .* ones(1,1,1,1, nfft) - CFRpath_phase_delay) );
            % If Ind_AntPhaseOffset =true, AntPhaseOffset is considered.
            if RFI.Ind_AntPhaseOffset == true
                Ind = Ang_Loc(iRr,iTr,1,:) >= -60 & Ang_Loc(iRr,iTr,1,:) <= 60;
                angle_temp = fix( Ang_Loc(iRr,iTr,1,:) *10 ) +601;
                temp1 = zeros(1,nTx,nRx,nslot,nfft);
                for islot = 1 : nslot
                    if Ind
                        temp = cat(2, zeros(1, 416, nRx), ...
                            RFI.PhOffset_intp( angle_temp(islot),(1: nfft -416),:) );
                    else
                        temp = 0;
                    end
                    temp1(1,:,:,islot,:) = permute(temp, [1 5 3 4 2] );
                end
                hfcoe_temp(1,:,:,:,:) = hfcoe_temp(1,:,:,:,:) .* ...
                    exp( 1i*  temp1 /180 *pi .* Ind  );
            end
            hfcoe = sum(hfcoe_temp, 1);
            hfcoe = permute(hfcoe, [5 2 3 4 1]);
            hfcoe = fftshift(hfcoe, 1);            % - nfft /2 ~ nfft /2 -1
            htcoe = ifft(hfcoe, nfft, 1);    % nDelayx * nTx * nRx * nRSslot
            nDelayx = round( max( PathDelay(:,1,1,1) * nfft * del_f ) ) +1 +20;
            nDelayx( nDelayx > nfft ) = nfft;
            CIR_cell{iRr, iTr} = htcoe(1: nDelayx,:,:,:);   % nDelayx * nTx * nRx * nRSslot
        else % CIR is generated by adjusting delay to the time-sample pos
            if size(PathDelay,2) == 1
                PathDelay = repmat(PathDelay, 1, nslot); % nP * nRSslot
            end
            nDelayx = max( max( round( PathDelay * nfft * del_f) +1) );
            CIR_temp = zeros( nDelayx, nTx, nRx, nslot);
            for islot = 1 : nslot
                idx_Chn = round( PathDelay(:, islot) * nfft * del_f ) +1 ;
                idx_Chn( idx_Chn > nfft ) = nfft;
                for iP = 1 : length(idx_Chn)
                    CIR_temp(idx_Chn(iP),:,:,islot) = ...
                        CIR_temp( idx_Chn(iP),:,:,islot) + PathCoeff(iP,:,:,islot);
                end
            end
            CIR_cell{iRr, iTr} = CIR_temp;           % nDelayx * nTx * nRx * nRSslot
        end
    end
end

end

%------------------------
% sub function
% used for antenna phase offset simulation only
%------------------------
function Ang_Loc = gen_localAngle(info,sysPar,nsnap);
% generate local path AOA for each BS; anticlockwise as +
Ang_Loc = zeros(sysPar.nRr, sysPar.nTr, 1, nsnap);
for iRr = 1 : sysPar.nRr
    for iTr = 1 : sysPar.nTr
        if sysPar.IndUplink
            if strcmpi(sysPar.UEstate,'dynamic')
                temp = info.ssp(iRr, iTr).cluster.phi_AOA_nt(1,:);
            else
                temp = info.ssp(iRr, iTr).cluster.phi_AOA_n(1,:);
            end
            Ang_Loc(iRr,iTr,1,:) = temp + sysPar.BSorientation(iRr) /pi *180 ...
                * ( ( temp >= 0)*(-1) + ( temp < 0) );
        else
            if strcmpi(sysPar.UEstate,'dynamic')
                temp = info.ssp(iTr, iRr).cluster.phi_AOD_nt(1,:);
            else
                temp = info.ssp(iTr, iRr).cluster.phi_AOD_n(1,:);
            end
            Ang_Loc(iRr,iTr,1,:) = temp + sysPar.BSorientation(iTr) /pi *180 ...
                * ( ( temp >= 0)*(-1) + ( temp < 0) );
        end
    end
end
end



