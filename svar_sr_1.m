%% 1. PRELIMINARIES
% -----------------------------------------------------------------------

clear all;

% Set LaTeX as the default interpreter for all figure text
set(groot,'defaultTextInterpreter','latex')
set(groot,'defaultAxesTickLabelInterpreter','latex')
set(groot,'defaultLegendInterpreter','latex')

% Helper for bold epsilon shock labels in figure text
bfeps = @(s) ['${\bf \epsilon}_{t}^{\mathrm{' s '}}$'];


%% 2. LOAD DATA
% -----------------------------------------------------------------------

raw = readcell('data_trim.xlsx', 'Sheet', 'Hoja1');


%% 2.1 DATA MATRIX
% -----------------------------------------------------------------------

data = cellfun(@double, raw(3:end, 2:end));
vnames = raw(1, 2:end);
mnem   = raw(2, 2:end);
nobs = size(data,1);
nvar = length(mnem);


%% 2.2 CREATE DATA STRUCTURE
% -----------------------------------------------------------------------

DATA = struct();
for ii = 1:nvar
    DATA.(mnem{ii}) = data(:,ii);
end


%% 2.3 OUTPUT GAP
% -----------------------------------------------------------------------

idx_igae = find(strcmpi(mnem,'igae'));
if isempty(idx_igae)
    error('No se encontró la variable IGAE en mnem.');
end

var_igae = data(:,idx_igae);
[trend,cyclical] = hpfilter(var_igae,Smoothing=1600);

DATA = rmfield(DATA,'igae');
DATA.brecha_prod = cyclical;


%% 2.4 CONSTRUCT X
% -----------------------------------------------------------------------

X = data;
X(:,idx_igae) = cyclical;


%% 2.5 UPDATE VARIABLE NAMES
% -----------------------------------------------------------------------

mnem{idx_igae} = 'brecha_prod';
vnames{idx_igae} = 'Brecha del producto';
nvar = length(mnem);


%% 2.6 DATES
% -----------------------------------------------------------------------

dates = raw(3:end,1);
firstdate_str = string(raw{3,1});
year = str2double(extractBetween(firstdate_str,1,4));
month = str2double(extractAfter(firstdate_str,'q'));
firstdate = year + (month-1)/12;


%% 3. PLOT SERIES
% -----------------------------------------------------------------------

figure;
FigSize(24,18)

for ii = 1:nvar
    subplot(ceil(nvar/2),2,ii)
    plot(DATA.(mnem{ii}), 'LineWidth',3, 'Color',pantone('Blue'));
    title(vnames{ii}, 'FontWeight','bold', 'FontSize',14);
    DatesPlot(firstdate,nobs,6,'q');
    set(gca,'FontSize',12,'Layer','bottom');
    grid on;
    set(findobj(gca,'Type','line'),'Clipping','off');
    SetAxesDual(gca);
end

%% 3.5 PRUEBA DE ESTACIONARIEDAD (ADF + KPSS)
% -----------------------------------------------------------------------

fprintf('\n=== Pruebas de estacionariedad ===\n');
fprintf('%-25s %10s %10s %10s %10s\n', 'Variable','ADF h','ADF p','KPSS h','KPSS p');

for ii = 1:nvar
    serie = X(:,ii);

    % ADF: H0 = raíz unitaria (no estacionaria). h=1 rechaza H0 -> estacionaria
    [h_adf, p_adf] = adftest(serie, 'model','ARD', 'lags',0:4);
    h_adf = h_adf(1); p_adf = p_adf(1);  % toma el primer rezago probado

    % KPSS: H0 = estacionaria. h=1 rechaza H0 -> NO estacionaria (lo opuesto a ADF)
    [h_kpss, p_kpss] = kpsstest(serie);

    fprintf('%-25s %10d %10.3f %10d %10.3f\n', ...
        vnames{ii}, h_adf, p_adf, h_kpss, p_kpss);
end



%% 3.8 SELECCIÓN DEL ORDEN DE REZAGOS ÓPTIMO
% -----------------------------------------------------------------------

detc   = 1;     % componente determinístico: 1=constante, 2=constante+tendencia
maxlag = 4;    % límite superior a evaluar (ajusta según T/10, ver nota abajo)
nlags = 1;
[AIC, BIC, logL] = VARlag(X, maxlag, detc);

fprintf('\n=== Selección de rezagos ===\n');
fprintf('Orden óptimo según AIC: %d\n', AIC);
fprintf('Orden óptimo según BIC: %d\n', BIC);

% --- Gráfica de log-verosimilitud por rezago ---
figure;
FigSize(20,12)
plot(1:maxlag, logL, '-o', 'LineWidth',2, 'Color',pantone('Blue'), ...
    'MarkerFaceColor',pantone('Blue'));
hold on
xline(AIC, '--', 'Color',pantone('Tomato'), 'LineWidth',1.5, 'Label','AIC');
xline(BIC, '--', 'Color',[0.3 0.3 0.3],      'LineWidth',1.5, 'Label','BIC');
hold off
xlabel('Orden de rezagos','FontSize',12);
ylabel('Log-verosimilitud','FontSize',12);
title('Selecci\''on del orden de rezagos','FontWeight','bold','FontSize',14);
grid on
set(gca,'FontSize',11,'Layer','bott');

SIGN = [ 1,   -1,  -1,  0, 0;  % Brecha
         1,    1,  -1,  0, 0;  % Inflacion
         1,    1,   1,  0, 0;  % Cetes 28
         0,    0,   0,  0, 0;  % Expectativas
         -1,    -1,  -1,  0, 1]; % Tipo de cambio

%% Opciones del VAR

VARopt          = VARoption;
VARopt.sr_hor   = 1;
VARopt.nsteps   = 10;
VARopt.mnem     = mnem;
VARopt.vnames   = vnames;
VARopt.figsize  = [24,18];
VARopt.subplot  = [3,2];
VARopt.dates    = dates;
VARopt.ident    = 'sign';

%% -----------------------------------------------------------------------
% Identificacion: SOLO RESTRICCIONES DE SIGNO
% -----------------------------------------------------------------------

VARopt_sr        = VARopt;
VARopt_sr.R      = SIGN;
VARopt_sr.ndraws = 3000;

VAR_sr = VARmodel(X, nlags, detc, VARopt_sr);

disp(['Tasa de aceptacion (solo signo): ' ...
      num2str(100*VAR_sr.accept_rate,'%.1f') '%'])


%% 5. IRFs + BANDAS 68%, 84% y 95% (PARA LOS 3 CHOQUES)
% -----------------------------------------------------------------------
nsteps = VARopt.nsteps;
x_axis = 0:nsteps-1;

%% ========================================================================
% EXTRAER IRFs ACEPTADAS (CONSERVAR TODOS LOS CHOQUES)
% ========================================================================
% La estructura es VAR_sr.IRall con dimensiones: [nsteps, nvar, nshocks, ndraws]
IRall_SR = VAR_sr.IRall(:,:,1:3,:);

%% ========================================================================
% MEDIANA Y PERCENTILES A LO LARGO DE LOS DRAWS (DIMENSIÓN 4)
% ========================================================================
IRmed_SR    = median(IRall_SR, 4);
IR68_SR_inf = prctile(IRall_SR, 16, 4);
IR68_SR_sup = prctile(IRall_SR, 84, 4);
IR84_SR_inf = prctile(IRall_SR, 8, 4);
IR84_SR_sup = prctile(IRall_SR, 92, 4);
IR95_SR_inf = prctile(IRall_SR, 2.5, 4);
IR95_SR_sup = prctile(IRall_SR, 97.5, 4);

%% ========================================================================
% COLOR
% ========================================================================
blue = pantone('Blue');

%% ========================================================================
% GRAFICA: BANDAS DE IDENTIFICACION PARA LOS 3 CHOQUES
% ========================================================================
for shock_to_plot = 1:3
    % Nombre del choque
    switch shock_to_plot
        case 1
            shock_name = 'demanda';
        case 2
            shock_name = 'oferta';
        case 3
            shock_name = 'política monetaria';
        otherwise
            shock_name = ['choque ' num2str(shock_to_plot)];
    end
    
    figure;
    FigSize(24,18)
    
    % Titulo general
    sgtitle(['Respuesta ante un choque de ' shock_name], ...
        'FontWeight','bold', ...
        'FontSize',18);
    
    for ii = 1:nvar
        subplot(ceil(nvar/2),2,ii)
        hold on
        
        %% ================================================================
        % COORDENADAS DE LAS BANDAS
        % =================================================================
        Xfill = [x_axis fliplr(x_axis)];
        
        %% ================================================================
        % BANDA 95%
        % =================================================================
        Y95_SR = [squeeze(IR95_SR_sup(:,ii,shock_to_plot))' ...
                  fliplr(squeeze(IR95_SR_inf(:,ii,shock_to_plot))')];
        H95 = fill(Xfill,Y95_SR,blue, ...
            'FaceAlpha',0.08, ...
            'EdgeColor','none');
        
        %% ================================================================
        % BANDA 84%
        % =================================================================
        Y84_SR = [squeeze(IR84_SR_sup(:,ii,shock_to_plot))' ...
                  fliplr(squeeze(IR84_SR_inf(:,ii,shock_to_plot))')];
        H84 = fill(Xfill,Y84_SR,blue, ...
            'FaceAlpha',0.12, ...
            'EdgeColor','none');
        
        %% ================================================================
        % BANDA 68%
        % =================================================================
        Y68_SR = [squeeze(IR68_SR_sup(:,ii,shock_to_plot))' ...
                  fliplr(squeeze(IR68_SR_inf(:,ii,shock_to_plot))')];
        H68 = fill(Xfill,Y68_SR,blue, ...
            'FaceAlpha',0.18, ...
            'EdgeColor','none');
        
        %% ================================================================
        % LINEA CERO Y MEDIANA
        % =================================================================
        H0 = yline(0,'k--','LineWidth',0.5);
        H1 = plot(x_axis,squeeze(IRmed_SR(:,ii,shock_to_plot)), ...
            'LineStyle','-', ...
            'Color',blue, ...
            'LineWidth',2, ...
            'Marker','o', ...
            'MarkerSize',5, ...
            'MarkerFaceColor',0.5*blue+0.5*[1 1 1], ...
            'MarkerEdgeColor',blue);
        
        %% ================================================================
        % FORMATO
        % ================================================================
        title(vnames{ii}, ...
            'FontWeight','bold', ...
            'FontSize',14);
        set(gca,'FontSize',12,'Layer','bottom');
        grid on
        xlim([0 nsteps-1])
        set(findobj(gca,'Type','line'),'Clipping','off');
        
        %% ================================================================
        % LEYENDA
        % ================================================================
        if ii == 1
            legend([H68 H84 H95], ...
                {'Banda 68%', ...
                 'Banda 84%', ...
                 'Banda 95%'}, ...
                'Location','southoutside', ...
                'Orientation','horizontal', ...
                'NumColumns',3);
        end
        hold off
    end
end

%% 6. FEVD (FORECAST ERROR VARIANCE DECOMPOSITION)
% -----------------------------------------------------------------------

% --- Modo 1: stacked area, todos los choques, un panel por variable ---
VARopt.pick    = 0;
VARopt.figname = 'graphics/sign_VD';
VARvdplot(VAR_sr.VDfp, VARopt);

% --- Modo 2: bandas de incertidumbre para el choque de política monetaria ---
% shock 3 = política monetaria (según tu matriz SIGN)
VARopt.pick    = 3;
VARopt.color   = pantone('Tomato');
VARopt.figname = 'graphics/sign_VD_bands_MonPol';
VARvdplot(VAR_sr.VDfp, VARopt, VAR_sr.VDinf, VAR_sr.VDsup);

% Resetear a los valores por defecto antes de reutilizar VARopt
VARopt.pick  = 0;
VARopt.color = [];


%% 7. HISTORICAL DECOMPOSITION
% -----------------------------------------------------------------------

% --- Modo 1: stacked area, todos los choques + componentes deterministas ---
VARopt.pick    = 0;
VARopt.figname = 'graphics/sign_HD';
VARhdplot(VAR_sr.HDfp, VARopt);

% --- Modo 2: bandas de incertidumbre, sólo la contribución de política monetaria ---
VARopt.pick    = 3;
VARopt.color   = pantone('Tomato');
VARopt.figname = 'graphics/sign_HD_bands_MonPol';
VARhdplot(VAR_sr.HDfp, VARopt, VAR_sr.HDinf, VAR_sr.HDsup);

VARopt.pick  = 0;
VARopt.color = [];


%% 8. RECUPERAR Y GUARDAR EL CHOQUE DE POLÍTICA MONETARIA
% -----------------------------------------------------------------------

% Usamos Bfp (rotación de Fry-Pagan): es la única matriz de impacto que
% corresponde a un draw genuino y por tanto es invertible de forma
% consistente con Sigma_u = B*B'. Bmed NO debe usarse para esto.
eps_sr = (VAR_sr.Bfp \ VAR_sr.resid')';   % T_eff x nvar, todos los choques estructurales

idx_monpol = 3;  % columna del choque de política monetaria en SIGN
shock_monpol = eps_sr(:, idx_monpol);

% Fechas correspondientes (se pierden los primeros nlags por los rezagos)
dates_shock = dates(nlags+1:end);

% Guardar para usarlo después (p.ej. como s_t en LP-OLS)
save('shock_monpol.mat', 'shock_monpol', 'dates_shock');

% Verificación rápida: los choques recuperados deben ser (aprox.) ortogonales
disp('Correlación entre choques estructurales (Fry-Pagan):')
disp(corr(eps_sr))