[xml]$Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Oliv_Maintenance" Width="1340" Height="860" MinWidth="640" MinHeight="480"
        WindowStartupLocation="CenterScreen" WindowStyle="SingleBorderWindow" ResizeMode="CanResize"
        Background="{DynamicResource BgBrush}" Foreground="{DynamicResource FgBrush}"
        FontFamily="Segoe UI" FontSize="13">
  <WindowChrome.WindowChrome>
    <WindowChrome CaptionHeight="56" ResizeBorderThickness="6" GlassFrameThickness="0" CornerRadius="0" UseAeroCaptionButtons="False"/>
  </WindowChrome.WindowChrome>
  <Window.Resources>
    <SolidColorBrush x:Key="BgBrush" Color="#1E1F22"/>
    <SolidColorBrush x:Key="PanelBrush" Color="#2B2D31"/>
    <SolidColorBrush x:Key="LineBrush" Color="#4A4E56"/>
    <SolidColorBrush x:Key="FgBrush" Color="#F2F3F5"/>
    <SolidColorBrush x:Key="MutedBrush" Color="#B5BAC1"/>
    <SolidColorBrush x:Key="AccentBrush" Color="#2563EB"/>
    <SolidColorBrush x:Key="HeadBrush" Color="#7AB8FF"/>
    <SolidColorBrush x:Key="BtnBrush" Color="#383A40"/>
    <SolidColorBrush x:Key="BtnHoverBrush" Color="#44474E"/>
    <SolidColorBrush x:Key="OnAccentBrush" Color="#FFFFFF"/>
    <SolidColorBrush x:Key="HoverBrush" Color="#35373C"/>
    <SolidColorBrush x:Key="ScrollBrush" Color="#5A5E66"/>
    <SolidColorBrush x:Key="CheckBorderBrush" Color="#8E939C"/>
    <SolidColorBrush x:Key="SelBrush" Color="#3B82F6"/>
    <SolidColorBrush x:Key="OkFgBrush" Color="#4ADE80"/>
    <SolidColorBrush x:Key="WarnFgBrush" Color="#FBBF24"/>
    <SolidColorBrush x:Key="ErrFgBrush" Color="#FCA5A5"/>
    <SolidColorBrush x:Key="PendBgBrush" Color="#3A2E14"/>
    <SolidColorBrush x:Key="ToggleOffBrush" Color="#7C818B"/>
    <SolidColorBrush x:Key="DisabledFgBrush" Color="#A3A8B0"/>

    <Style x:Key="HoverPlain" TargetType="Border">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="CornerRadius" Value="6"/>
      <Setter Property="Margin" Value="0,1"/>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Background" Value="{DynamicResource HoverBrush}"/>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="HoverLine" TargetType="Border">
      <Setter Property="Background" Value="Transparent"/>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Background" Value="{DynamicResource HoverBrush}"/>
        </Trigger>
      </Style.Triggers>
    </Style>
    <!-- ligne de la liste des services : comme HoverPlain, mais hors de l'index de la recherche globale -->
    <Style x:Key="SvcRow" TargetType="Border">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="CornerRadius" Value="6"/>
      <Setter Property="Margin" Value="0,1"/>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Background" Value="{DynamicResource HoverBrush}"/>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="HoverRow" TargetType="Border">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="CornerRadius" Value="6"/>
      <Setter Property="Margin" Value="0,1"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Background" Value="{DynamicResource HoverBrush}"/>
        </Trigger>
      </Style.Triggers>
    </Style>

    <Style x:Key="NavBtn" TargetType="Button">
      <!-- info-bulle aussi sur un bouton grisé : elle donne la raison -->
      <Setter Property="ToolTipService.ShowOnDisabled" Value="True"/>
      <Setter Property="Foreground" Value="{DynamicResource FgBrush}"/>
      <Setter Property="Background" Value="{DynamicResource BtnBrush}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource LineBrush}"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Width" Value="132"/>
      <Setter Property="Height" Value="34"/>
      <Setter Property="Margin" Value="0,0,6,0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="WindowChrome.IsHitTestVisibleInChrome" Value="True"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="4" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource BtnHoverBrush}"/>
              </Trigger>
              <!-- inactif : sans fond, texte et contour estompés, pour tous les boutons (gris, bleus, rouges) -->
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Background" Value="Transparent"/>
                <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource LineBrush}"/>
                <Setter Property="Foreground" Value="{DynamicResource DisabledFgBrush}"/>
                <Setter Property="Opacity" Value="0.85"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="Tag" Value="on">
          <Setter Property="Background" Value="{DynamicResource AccentBrush}"/>
          <Setter Property="Foreground" Value="{DynamicResource OnAccentBrush}"/>
        </Trigger>
      </Style.Triggers>
    </Style>

    <Style x:Key="ActionBtn" TargetType="Button" BasedOn="{StaticResource NavBtn}">
      <Setter Property="Width" Value="Auto"/>
      <Setter Property="MinWidth" Value="110"/>
      <Setter Property="Height" Value="32"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="FontWeight" Value="Normal"/>
      <Setter Property="Padding" Value="14,0"/>
    </Style>

    <Style x:Key="PrimaryBtn" TargetType="Button" BasedOn="{StaticResource ActionBtn}">
      <Setter Property="Background" Value="{DynamicResource AccentBrush}"/>
      <Setter Property="Foreground" Value="{DynamicResource OnAccentBrush}"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>

    <Style x:Key="IconBtn" TargetType="Button" BasedOn="{StaticResource NavBtn}">
      <Setter Property="Width" Value="40"/>
      <Setter Property="Height" Value="34"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderBrush" Value="Transparent"/>
      <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="FontWeight" Value="Normal"/>
      <Setter Property="Margin" Value="2,0"/>
    </Style>

    <Style x:Key="Section" TargetType="TextBlock">
      <Setter Property="TextWrapping" Value="Wrap"/>
      <Setter Property="FontSize" Value="16"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="{DynamicResource FgBrush}"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
    <Style x:Key="CardIcon" TargetType="TextBlock">
      <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/>
      <Setter Property="FontSize" Value="18"/>
      <Setter Property="Foreground" Value="{DynamicResource HeadBrush}"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="Margin" Value="0,0,12,0"/>
    </Style>

    <Style x:Key="TabBtn" TargetType="Button">
      <Setter Property="Foreground" Value="{DynamicResource MutedBrush}"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Height" Value="40"/>
      <Setter Property="Padding" Value="14,0"/>
      <Setter Property="Margin" Value="0,0,4,0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="WindowChrome.IsHitTestVisibleInChrome" Value="True"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Grid>
              <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="6" Padding="{TemplateBinding Padding}">
                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource HoverBrush}"/>
                <Setter Property="Foreground" Value="{DynamicResource FgBrush}"/>
              </Trigger>
              <Trigger Property="Tag" Value="on">
                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource BtnBrush}"/>
                <Setter Property="Foreground" Value="{DynamicResource FgBrush}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Ligne de menu déroulant (choix du thème) -->
    <Style x:Key="MenuRow" TargetType="Button">
      <Setter Property="Foreground" Value="{DynamicResource FgBrush}"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="Transparent" CornerRadius="4" Padding="8,7,16,7">
              <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource HoverBrush}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="CloseBtn" TargetType="Button" BasedOn="{StaticResource IconBtn}">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="Transparent" CornerRadius="4">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#C42B1C"/>
                <Setter Property="Foreground" Value="White"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="WarnBtn" TargetType="Button" BasedOn="{StaticResource ActionBtn}">
      <Setter Property="Foreground" Value="{DynamicResource ErrFgBrush}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource ErrFgBrush}"/>
    </Style>

    <Style x:Key="Muted" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{DynamicResource MutedBrush}"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
    </Style>

    <Style x:Key="TaskCheck" TargetType="CheckBox">
      <Setter Property="Foreground" Value="{DynamicResource FgBrush}"/>
      <Setter Property="Margin" Value="0,3"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
      <Setter Property="ToolTipService.InitialShowDelay" Value="250"/>
      <Setter Property="ToolTipService.ShowDuration" Value="30000"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <StackPanel Orientation="Horizontal" Background="Transparent">
              <Border x:Name="Box" Width="18" Height="18" CornerRadius="4" BorderThickness="1.5"
                      BorderBrush="{DynamicResource CheckBorderBrush}" Background="{DynamicResource PanelBrush}"
                      VerticalAlignment="{TemplateBinding VerticalContentAlignment}">
                <TextBlock x:Name="Mark" FontFamily="Segoe MDL2 Assets" FontSize="11" Foreground="White"
                           HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <ContentPresenter Margin="8,0,0,0" VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Box" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Box" Property="Background" Value="{DynamicResource AccentBrush}"/>
                <Setter TargetName="Box" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
                <Setter TargetName="Mark" Property="Text" Value="&#xE73E;"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="{x:Null}">
                <Setter TargetName="Box" Property="Background" Value="{DynamicResource AccentBrush}"/>
                <Setter TargetName="Box" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
                <Setter TargetName="Mark" Property="Text" Value="&#xE738;"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.6"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Toggle" TargetType="CheckBox">
      <Setter Property="Foreground" Value="{DynamicResource FgBrush}"/>
      <Setter Property="Margin" Value="0,2"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="ToolTipService.ShowDuration" Value="30000"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <StackPanel Orientation="Horizontal" Background="Transparent">
              <Border x:Name="Track" Width="40" Height="20" CornerRadius="10" Background="{DynamicResource ToggleOffBrush}" VerticalAlignment="Center">
                <Ellipse x:Name="Knob" Width="12" Height="12" Fill="White" HorizontalAlignment="Left" Margin="4,0,0,0"/>
              </Border>
              <ContentPresenter Margin="10,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Track" Property="Background" Value="{DynamicResource AccentBrush}"/>
                <Setter TargetName="Knob" Property="HorizontalAlignment" Value="Right"/>
                <Setter TargetName="Knob" Property="Margin" Value="0,0,4,0"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.6"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Panel" TargetType="Border">
      <Setter Property="Background" Value="{DynamicResource PanelBrush}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource LineBrush}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="8"/>
    </Style>

    <Style x:Key="Console" TargetType="TextBox">
      <Setter Property="IsReadOnly" Value="True"/>
      <Setter Property="FontFamily" Value="Consolas"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Background" Value="{DynamicResource PanelBrush}"/>
      <Setter Property="Foreground" Value="{DynamicResource FgBrush}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource LineBrush}"/>
      <Setter Property="Padding" Value="10"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
      <Setter Property="VerticalScrollBarVisibility" Value="Auto"/>
      <Setter Property="HorizontalScrollBarVisibility" Value="Disabled"/>
      <Setter Property="SelectionBrush" Value="{DynamicResource SelBrush}"/>
      <Setter Property="CaretBrush" Value="{DynamicResource FgBrush}"/>
    </Style>

    <Style TargetType="TextBox">
      <Setter Property="SelectionBrush" Value="{DynamicResource SelBrush}"/>
      <Setter Property="SelectionOpacity" Value="0.45"/>
    </Style>
    <Style TargetType="ToolTip">
      <Setter Property="Background" Value="{DynamicResource PanelBrush}"/>
      <Setter Property="Foreground" Value="{DynamicResource FgBrush}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource LineBrush}"/>
      <Setter Property="Padding" Value="10,6"/>
      <Setter Property="MaxWidth" Value="560"/>
      <Setter Property="ContentTemplate">
        <Setter.Value>
          <DataTemplate>
            <TextBlock Text="{Binding}" TextWrapping="Wrap"/>
          </DataTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ContextMenu">
      <Setter Property="Background" Value="{DynamicResource PanelBrush}"/>
      <Setter Property="Foreground" Value="{DynamicResource FgBrush}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource LineBrush}"/>
    </Style>
    <Style TargetType="ScrollBar">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Width" Value="12"/>
      <Setter Property="MinWidth" Value="12"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Grid Background="{TemplateBinding Background}">
              <Track x:Name="PART_Track" IsDirectionReversed="True">
                <Track.DecreaseRepeatButton>
                  <RepeatButton Command="ScrollBar.PageUpCommand" Opacity="0" Focusable="False"/>
                </Track.DecreaseRepeatButton>
                <Track.IncreaseRepeatButton>
                  <RepeatButton Command="ScrollBar.PageDownCommand" Opacity="0" Focusable="False"/>
                </Track.IncreaseRepeatButton>
                <Track.Thumb>
                  <Thumb>
                    <Thumb.Template>
                      <ControlTemplate TargetType="Thumb">
                        <Border x:Name="T" CornerRadius="4" Margin="3,2" Background="{DynamicResource ScrollBrush}"/>
                        <ControlTemplate.Triggers>
                          <Trigger Property="IsMouseOver" Value="True">
                            <Setter TargetName="T" Property="Background" Value="{DynamicResource MutedBrush}"/>
                          </Trigger>
                        </ControlTemplate.Triggers>
                      </ControlTemplate>
                    </Thumb.Template>
                  </Thumb>
                </Track.Thumb>
              </Track>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="Orientation" Value="Horizontal">
          <Setter Property="Width" Value="Auto"/>
          <Setter Property="MinWidth" Value="0"/>
          <Setter Property="Height" Value="12"/>
          <Setter Property="MinHeight" Value="12"/>
          <Setter Property="Template">
            <Setter.Value>
              <ControlTemplate TargetType="ScrollBar">
                <Grid Background="{TemplateBinding Background}">
                  <Track x:Name="PART_Track" IsDirectionReversed="False">
                    <Track.DecreaseRepeatButton>
                      <RepeatButton Command="ScrollBar.PageLeftCommand" Opacity="0" Focusable="False"/>
                    </Track.DecreaseRepeatButton>
                    <Track.IncreaseRepeatButton>
                      <RepeatButton Command="ScrollBar.PageRightCommand" Opacity="0" Focusable="False"/>
                    </Track.IncreaseRepeatButton>
                    <Track.Thumb>
                      <Thumb>
                        <Thumb.Template>
                          <ControlTemplate TargetType="Thumb">
                            <Border x:Name="T" CornerRadius="4" Margin="2,3" Background="{DynamicResource ScrollBrush}"/>
                            <ControlTemplate.Triggers>
                              <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="T" Property="Background" Value="{DynamicResource MutedBrush}"/>
                              </Trigger>
                            </ControlTemplate.Triggers>
                          </ControlTemplate>
                        </Thumb.Template>
                      </Thumb>
                    </Track.Thumb>
                  </Track>
                </Grid>
              </ControlTemplate>
            </Setter.Value>
          </Setter>
        </Trigger>
      </Style.Triggers>
    </Style>
  </Window.Resources>

  <Border x:Name="RootBorder" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <Grid x:Name="HeaderBar" Grid.Row="0" Background="{DynamicResource PanelBrush}" Height="56">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <Canvas x:Name="TabCanvas" Grid.Column="0" IsHitTestVisible="False" Panel.ZIndex="1">
          <Border x:Name="TabIndicator" Width="20" Height="3" CornerRadius="1.5" Background="{DynamicResource HeadBrush}" Visibility="Hidden"/>
        </Canvas>
        <StackPanel x:Name="TabStrip" Orientation="Horizontal" VerticalAlignment="Center" Margin="12,0,0,0">
          <Image x:Name="HeadLogo" Width="30" Height="30" Margin="4,0,12,0" VerticalAlignment="Center" RenderOptions.BitmapScalingMode="HighQuality" Visibility="Collapsed"/>
          <Button x:Name="NavInfo" Style="{StaticResource TabBtn}" Tag="on">
            <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE80F;" FontFamily="Segoe MDL2 Assets" FontSize="14" VerticalAlignment="Center" Margin="0,0,8,0"/><TextBlock TextWrapping="Wrap" Text="Accueil" VerticalAlignment="Center"/></StackPanel>
          </Button>
          <Button x:Name="NavMaint" Style="{StaticResource TabBtn}">
            <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE90F;" FontFamily="Segoe MDL2 Assets" FontSize="14" VerticalAlignment="Center" Margin="0,0,8,0"/><TextBlock TextWrapping="Wrap" Text="Maintenance" VerticalAlignment="Center"/></StackPanel>
          </Button>
          <Button x:Name="NavPerf" Style="{StaticResource TabBtn}">
            <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE770;" FontFamily="Segoe MDL2 Assets" FontSize="14" VerticalAlignment="Center" Margin="0,0,8,0"/><TextBlock TextWrapping="Wrap" Text="Système" VerticalAlignment="Center"/></StackPanel>
          </Button>
          <Button x:Name="NavSecu" Style="{StaticResource TabBtn}">
            <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE72E;" FontFamily="Segoe MDL2 Assets" FontSize="14" VerticalAlignment="Center" Margin="0,0,8,0"/><TextBlock TextWrapping="Wrap" Text="Sécurité" VerticalAlignment="Center"/></StackPanel>
          </Button>
          <Button x:Name="NavPerso" Style="{StaticResource TabBtn}">
            <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE771;" FontFamily="Segoe MDL2 Assets" FontSize="14" VerticalAlignment="Center" Margin="0,0,8,0"/><TextBlock TextWrapping="Wrap" Text="Personnalisation" VerticalAlignment="Center"/></StackPanel>
          </Button>
          <Button x:Name="NavApps" Style="{StaticResource TabBtn}">
            <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE71D;" FontFamily="Segoe MDL2 Assets" FontSize="14" VerticalAlignment="Center" Margin="0,0,8,0"/><TextBlock TextWrapping="Wrap" Text="Applications" VerticalAlignment="Center"/></StackPanel>
          </Button>
          <Button x:Name="NavSvc" Style="{StaticResource TabBtn}">
            <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE912;" FontFamily="Segoe MDL2 Assets" FontSize="14" VerticalAlignment="Center" Margin="0,0,8,0"/><TextBlock TextWrapping="Wrap" Text="Services et tâches" VerticalAlignment="Center"/></StackPanel>
          </Button>
          <Button x:Name="NavTools" Style="{StaticResource TabBtn}">
            <StackPanel Orientation="Horizontal"><TextBlock Text="&#xEC7A;" FontFamily="Segoe MDL2 Assets" FontSize="14" VerticalAlignment="Center" Margin="0,0,8,0"/><TextBlock TextWrapping="Wrap" Text="Outils" VerticalAlignment="Center"/></StackPanel>
          </Button>
          <Button x:Name="NavLog" Style="{StaticResource TabBtn}">
            <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE81C;" FontFamily="Segoe MDL2 Assets" FontSize="14" VerticalAlignment="Center" Margin="0,0,8,0"/><TextBlock TextWrapping="Wrap" Text="Journal" VerticalAlignment="Center"/></StackPanel>
          </Button>
        </StackPanel>
        <!-- recherche globale : champ arrondi centré dans l'en-tête, cliquable malgré la zone de titre (WindowChrome) -->
        <Border x:Name="SearchBox" Grid.Column="1" HorizontalAlignment="Center" VerticalAlignment="Center" Width="360" Height="36" Margin="12,0,12,0"
                CornerRadius="18" Background="{DynamicResource BgBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1.5" WindowChrome.IsHitTestVisibleInChrome="True" Cursor="IBeam">
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <TextBlock Text="&#xE721;" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="{DynamicResource AccentBrush}" Margin="14,0,8,0" VerticalAlignment="Center"/>
            <!-- gabarit minimal : aucun fond ni cadre système au focus, seul le texte et le curseur s'affichent -->
            <TextBox x:Name="GlobalSearch" Grid.Column="1" BorderThickness="0" Background="Transparent" Foreground="{DynamicResource FgBrush}" CaretBrush="{DynamicResource FgBrush}" VerticalAlignment="Center" VerticalContentAlignment="Center" Padding="0" FontSize="13">
              <TextBox.Template>
                <ControlTemplate TargetType="TextBox">
                  <ScrollViewer x:Name="PART_ContentHost" Focusable="False" HorizontalScrollBarVisibility="Hidden" VerticalScrollBarVisibility="Hidden" Background="Transparent"/>
                </ControlTemplate>
              </TextBox.Template>
            </TextBox>
            <TextBlock x:Name="SearchHint" Grid.Column="1" Text="Rechercher dans l&apos;application" Foreground="{DynamicResource MutedBrush}" VerticalAlignment="Center" IsHitTestVisible="False" TextTrimming="CharacterEllipsis"/>
            <Border x:Name="SearchKey" Grid.Column="2" Margin="8,0,12,0" Padding="6,1,6,1" CornerRadius="4" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" VerticalAlignment="Center" IsHitTestVisible="False">
              <TextBlock Text="Ctrl+F" FontSize="11" Foreground="{DynamicResource MutedBrush}"/>
            </Border>
            <Popup x:Name="SearchPop" PopupAnimation="Fade" PlacementTarget="{Binding ElementName=SearchBox}" Placement="Bottom" StaysOpen="False" AllowsTransparency="True" VerticalOffset="6" HorizontalOffset="-60">
              <Border Width="480" Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="10" Margin="0,0,14,14">
                <Border.Effect><DropShadowEffect BlurRadius="18" ShadowDepth="4" Opacity="0.28"/></Border.Effect>
                <DockPanel>
                  <Border DockPanel.Dock="Bottom" BorderBrush="{DynamicResource LineBrush}" BorderThickness="0,1,0,0" Padding="14,7,14,8">
                    <TextBlock x:Name="SearchFoot" FontSize="11" Foreground="{DynamicResource MutedBrush}" Text="&#x2191;&#x2193; pour choisir  &#xB7;  Entrée pour ouvrir  &#xB7;  Échap pour fermer"/>
                  </Border>
                  <ScrollViewer MaxHeight="520" VerticalScrollBarVisibility="Auto"><StackPanel x:Name="SearchList" Margin="6"/></ScrollViewer>
                </DockPanel>
              </Border>
            </Popup>
          </Grid>
        </Border>
        <StackPanel Grid.Column="3" Orientation="Horizontal" VerticalAlignment="Center" Margin="0,0,6,0">
          <Button x:Name="SearchIconBtn" Content="&#xE721;" Style="{StaticResource IconBtn}" ToolTip="Rechercher dans l&apos;application (Ctrl+F)" Visibility="Collapsed"/>
          <Button x:Name="ThemeBtn" Content="&#xE713;" Style="{StaticResource IconBtn}" ToolTip="Paramètres"/>
          <Button x:Name="MinBtn" Content="&#xE921;" Style="{StaticResource IconBtn}" ToolTip="Réduire"/>
          <Button x:Name="MaxBtn" Content="&#xE922;" Style="{StaticResource IconBtn}" ToolTip="Agrandir"/>
          <Button x:Name="CloseBtn" Content="&#xE8BB;" Style="{StaticResource CloseBtn}" ToolTip="Fermer"/>
        </StackPanel>
      </Grid>

      <Border Grid.Row="1" Background="{DynamicResource BgBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="0,1,0,1" Padding="16,6">
        <TextBlock x:Name="AppInfo" Foreground="{DynamicResource MutedBrush}" FontSize="12" HorizontalAlignment="Center" TextAlignment="Center" TextWrapping="NoWrap" TextTrimming="CharacterEllipsis"/>
      </Border>

      <Border x:Name="PendingBar" Grid.Row="2" Background="{DynamicResource PendBgBrush}" BorderBrush="{DynamicResource WarnFgBrush}" BorderThickness="0,0,0,1" Padding="16,6" Visibility="Collapsed">
        <DockPanel LastChildFill="True">
          <Button x:Name="PendingReboot" DockPanel.Dock="Right" Content="Redémarrer le poste" Style="{StaticResource ActionBtn}" Height="28" Margin="6,0,0,0"/>
          <Button x:Name="PendingLogoff" DockPanel.Dock="Right" Content="Se déconnecter" Style="{StaticResource ActionBtn}" Height="28" Margin="6,0,0,0"/>
          <Button x:Name="PendingExplorer" DockPanel.Dock="Right" Content="Redémarrer l'Explorateur" Style="{StaticResource ActionBtn}" Height="28" Margin="6,0,0,0"/>
          <TextBlock x:Name="PendingText" Foreground="{DynamicResource WarnFgBrush}" FontWeight="SemiBold" VerticalAlignment="Center" TextWrapping="Wrap"/>
        </DockPanel>
      </Border>

      <!-- nouvelle version publiée sur GitHub : bandeau proposant la mise à jour (94-mise-a-jour.ps1) -->
      <StackPanel Grid.Row="3">
      <!-- opérations longues en arrière-plan (chiffrement BitLocker, analyse antivirus) : avancement visible de tous les onglets -->
      <Border x:Name="BgBar" Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="0,0,0,1" Padding="16,6,16,8" Visibility="Collapsed">
        <StackPanel x:Name="BgList"/>
      </Border>
      <Border x:Name="UpdBar" Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource AccentBrush}" BorderThickness="0,0,0,2" Padding="16,6" Visibility="Collapsed">
        <DockPanel LastChildFill="True">
          <Button x:Name="UpdLater" DockPanel.Dock="Right" Content="Plus tard" Style="{StaticResource ActionBtn}" Height="28" Margin="6,0,0,0"/>
          <Button x:Name="UpdNotes" DockPanel.Dock="Right" Content="Nouveautés" Style="{StaticResource ActionBtn}" Height="28" Margin="6,0,0,0"/>
          <Button x:Name="UpdGo" DockPanel.Dock="Right" Content="Mettre à jour" Style="{StaticResource PrimaryBtn}" Height="28" Margin="6,0,0,0"/>
          <ProgressBar x:Name="UpdProg" DockPanel.Dock="Bottom" Height="3" Margin="0,5,0,0" Visibility="Collapsed" Foreground="{DynamicResource AccentBrush}" Background="Transparent" BorderThickness="0"/>
          <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
            <TextBlock Text="&#xE896;" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="{DynamicResource AccentBrush}" VerticalAlignment="Center" Margin="0,0,10,0"/>
            <TextBlock x:Name="UpdText" FontWeight="SemiBold" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
          </StackPanel>
        </DockPanel>
      </Border>
      </StackPanel>

      <Grid Grid.Row="4" Margin="14,10,14,10">

        <Grid x:Name="PageMaint" Visibility="Collapsed">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="12"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>
          <DockPanel x:Name="MaintLeft" Grid.Column="0" VerticalAlignment="Top">
          <Border DockPanel.Dock="Bottom" Style="{StaticResource Panel}" Padding="16,14,16,14" Margin="0,12,0,0">
            <Grid>
              <StackPanel VerticalAlignment="Center" Margin="0,0,130,0">
                <DockPanel><TextBlock Text="&#xEDA2;" Style="{StaticResource CardIcon}" DockPanel.Dock="Left"/><TextBlock TextWrapping="Wrap" Text="Espace disque" Style="{StaticResource Section}"/></DockPanel>
                <TextBlock Style="{StaticResource Muted}" Margin="30,4,0,0" TextWrapping="Wrap" Text="Taille des dossiers et fichiers d&apos;un volume ou d&apos;un dossier, vue en blocs proportionnels"/>
              </StackPanel>
              <Button x:Name="SpaceBtn" Content="Analyser" Style="{StaticResource ActionBtn}" MinWidth="110" Margin="0,0,14,0" HorizontalAlignment="Right" VerticalAlignment="Center"/>
            </Grid>
          </Border>
          <Border Style="{StaticResource Panel}" VerticalAlignment="Top">
            <Grid>
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
              </Grid.RowDefinitions>
              <Grid Margin="16,14,16,8">
                <DockPanel><TextBlock Text="&#xE74D;" Style="{StaticResource CardIcon}" DockPanel.Dock="Left"/><TextBlock TextWrapping="Wrap" Text="Nettoyage" Style="{StaticResource Section}"/></DockPanel>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                  <TextBlock TextWrapping="Wrap" x:Name="CleanScanText" Style="{StaticResource Muted}" VerticalAlignment="Center" Margin="0,0,8,0"/>
                  <Button x:Name="CleanRescan" Content="&#xE72C;" Style="{StaticResource IconBtn}" Width="32" Height="30" Margin="2,0,-6,0" ToolTip="Actualiser"/>
                </StackPanel>
              </Grid>
              <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
                <StackPanel x:Name="CleanTree" Margin="12,0,14,8"/>
              </ScrollViewer>
              <Border Grid.Row="2" BorderBrush="{DynamicResource LineBrush}" BorderThickness="0,1,0,0" Padding="18,8">
                <Grid>
                  <TextBlock TextWrapping="Wrap" x:Name="CleanFree" Style="{StaticResource Muted}" FontSize="13"/>
                  <TextBlock TextWrapping="Wrap" x:Name="CleanSel" Style="{StaticResource Muted}" FontSize="13" HorizontalAlignment="Right"/>
                </Grid>
              </Border>
            </Grid>
          </Border>
          </DockPanel>
          <Border x:Name="MaintRight" Grid.Column="2">
            <ScrollViewer VerticalScrollBarVisibility="Auto">
              <StackPanel x:Name="MaintCards">
                <Border Style="{StaticResource Panel}" Padding="16,14,16,14" Margin="0,0,0,12">
                <StackPanel>
                <Grid>
                  <StackPanel>
                    <DockPanel><TextBlock Text="&#xE90F;" Style="{StaticResource CardIcon}" DockPanel.Dock="Left"/><TextBlock TextWrapping="Wrap" Text="Réparation" Style="{StaticResource Section}"/></DockPanel>
                    <TextBlock TextWrapping="Wrap" Style="{StaticResource Muted}" Margin="30,4,0,0" Text="Plantages, gels, écrans bleus, mises à jour en échec"/>
                  </StackPanel>
                  <TextBlock Text="&#xE946;" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="{DynamicResource MutedBrush}" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,2,4,0"
                             ToolTipService.ShowDuration="60000"
                             ToolTip="Analyser : DISM /ScanHealth, SFC /verifyonly.&#x0a;Réparer : DISM /RestoreHealth, SFC /scannow.&#x0a;CHKDSK Analyser : état du volume (bit dirty, événements NTFS 55 / 98).&#x0a;CHKDSK Réparer : /F programmé au prochain démarrage (fsutil dirty set)."/>
                </Grid>
                <StackPanel x:Name="RepairList" Margin="0,8,0,0"/>
                <Grid Margin="0,10,0,0">
                  <TextBlock TextWrapping="Wrap" x:Name="RepairStatus" Style="{StaticResource Muted}" FontSize="13" VerticalAlignment="Center" Margin="0,0,360,0"/>
                  <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                    <TextBlock x:Name="RepairLast" Style="{StaticResource Muted}" FontSize="11" TextAlignment="Right" TextWrapping="NoWrap" VerticalAlignment="Center" Margin="0,0,12,0"/>
                    <Button x:Name="RepairScanBtn" Content="Analyser" Style="{StaticResource ActionBtn}" Margin="0,0,6,0" IsEnabled="False"/>
                    <Button x:Name="RepairFixBtn" Content="Réparer" Style="{StaticResource PrimaryBtn}" IsEnabled="False"/>
                  </StackPanel>
                </Grid>

                </StackPanel>
                </Border>
                <Border Style="{StaticResource Panel}" Padding="16,14,16,10" Margin="0,0,0,12">
                <StackPanel>
                <DockPanel Margin="0,0,0,6"><TextBlock Text="&#xEDA2;" Style="{StaticResource CardIcon}" DockPanel.Dock="Left"/><TextBlock x:Name="DiskCardTitle" TextWrapping="Wrap" Text="Disques et batterie" Style="{StaticResource Section}"/></DockPanel>
                <Border Style="{StaticResource HoverPlain}">
                  <Grid Margin="8,4">
                    <StackPanel VerticalAlignment="Center" Margin="0,0,330,0">
                      <TextBlock TextWrapping="Wrap" Text="État de santé des disques (SMART)" FontWeight="SemiBold"/>
                      <TextBlock TextWrapping="Wrap" x:Name="SmartStatus" Style="{StaticResource Muted}" Text="Santé, température, usure, heures de fonctionnement, erreurs"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                      <TextBlock x:Name="SmartLast" Style="{StaticResource Muted}" FontSize="11" TextAlignment="Right" TextWrapping="NoWrap" VerticalAlignment="Center" Margin="0,0,12,0"/>
                      <Button x:Name="SmartBtn" Content="Analyser" Style="{StaticResource ActionBtn}" Margin="0,0,6,0" MinWidth="96"/>
                      <Button x:Name="SmartOpenBtn" Content="Ouvrir" Style="{StaticResource ActionBtn}" MinWidth="96" IsEnabled="False" ToolTip="Dernier rapport SMART"/>
                    </StackPanel>
                  </Grid>
                </Border>
                <Border Style="{StaticResource HoverPlain}">
                  <Grid Margin="8,4">
                    <StackPanel VerticalAlignment="Center" Margin="0,0,250,0">
                      <TextBlock TextWrapping="Wrap" Text="Optimisation du disque système" FontWeight="SemiBold"/>
                      <TextBlock TextWrapping="Wrap" x:Name="OptimizeStatus" Style="{StaticResource Muted}" Tag="TRIM sur SSD, défragmentation sur disque dur" Text="TRIM sur SSD, défragmentation sur disque dur"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                      <TextBlock x:Name="OptimizeLast" Style="{StaticResource Muted}" FontSize="11" TextAlignment="Right" TextWrapping="NoWrap" VerticalAlignment="Center" Margin="0,0,12,0"/>
                      <Button x:Name="OptimizeBtn" Content="Optimiser" Style="{StaticResource ActionBtn}" MinWidth="96"/>
                    </StackPanel>
                  </Grid>
                </Border>
                <Border Style="{StaticResource HoverPlain}">
                  <Grid Margin="8,4">
                    <StackPanel VerticalAlignment="Center" Margin="0,0,330,0">
                      <TextBlock TextWrapping="Wrap" Text="Rapport de batterie" FontWeight="SemiBold"/>
                      <TextBlock TextWrapping="Wrap" x:Name="BatteryStatus" Style="{StaticResource Muted}" Text="Capacité d&apos;origine et actuelle, usure, historique d&apos;utilisation"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                      <TextBlock x:Name="BatteryLast" Style="{StaticResource Muted}" FontSize="11" TextAlignment="Right" TextWrapping="NoWrap" VerticalAlignment="Center" Margin="0,0,12,0"/>
                      <Button x:Name="BatteryBtn" Content="Générer" Style="{StaticResource ActionBtn}" Margin="0,0,6,0" MinWidth="96"/>
                      <Button x:Name="BatteryOpenBtn" Content="Ouvrir" Style="{StaticResource ActionBtn}" MinWidth="96" IsEnabled="False" ToolTip="Dernier rapport batterie"/>
                    </StackPanel>
                  </Grid>
                </Border>

                </StackPanel>
                </Border>
                <Border Style="{StaticResource Panel}" Padding="16,14,16,10" Margin="0,0,0,12">
                <StackPanel>
                <DockPanel Margin="0,0,0,6"><TextBlock Text="&#xE7BA;" Style="{StaticResource CardIcon}" DockPanel.Dock="Left"/><TextBlock TextWrapping="Wrap" Text="Dépannage" Style="{StaticResource Section}"/></DockPanel>
                <Border Style="{StaticResource HoverPlain}">
                  <Grid Margin="8,4">
                    <StackPanel VerticalAlignment="Center" Margin="0,0,250,0">
                      <TextBlock TextWrapping="Wrap" Text="Composants Windows Update" FontWeight="SemiBold"/>
                      <TextBlock TextWrapping="Wrap" x:Name="WuResetStatus" Style="{StaticResource Muted}" Tag="Mises à jour bloquées ou en échec : services, files BITS, DataStore, Download et catroot2 réinitialisés" Text="Mises à jour bloquées ou en échec : services, files BITS, DataStore, Download et catroot2 réinitialisés"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                      <TextBlock x:Name="WuResetLast" Style="{StaticResource Muted}" FontSize="11" TextAlignment="Right" TextWrapping="NoWrap" VerticalAlignment="Center" Margin="0,0,12,0"/>
                      <Button x:Name="WuResetBtn" Content="Réinitialiser" Style="{StaticResource WarnBtn}" MinWidth="96"/>
                    </StackPanel>
                  </Grid>
                </Border>
                <Border Style="{StaticResource HoverPlain}">
                  <Grid Margin="8,4">
                    <StackPanel VerticalAlignment="Center" Margin="0,0,250,0">
                      <TextBlock TextWrapping="Wrap" Text="Diagnostic réseau" FontWeight="SemiBold"/>
                      <TextBlock TextWrapping="Wrap" x:Name="NetCheckStatus" Style="{StaticResource Muted}" Tag="Pas d&apos;accès réseau ou Internet : carte, passerelle, DNS, domaine et Internet testés pas à pas" Text="Pas d&apos;accès réseau ou Internet : carte, passerelle, DNS, domaine et Internet testés pas à pas"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                      <TextBlock x:Name="NetCheckLast" Style="{StaticResource Muted}" FontSize="11" TextAlignment="Right" TextWrapping="NoWrap" VerticalAlignment="Center" Margin="0,0,12,0"/>
                      <Button x:Name="NetCheckBtn" Content="Tester" Style="{StaticResource ActionBtn}" MinWidth="96"/>
                    </StackPanel>
                  </Grid>
                </Border>
                <Border Style="{StaticResource HoverPlain}">
                  <Grid Margin="8,4">
                    <StackPanel VerticalAlignment="Center" Margin="0,0,250,0">
                      <TextBlock TextWrapping="Wrap" Text="Microsoft Store" FontWeight="SemiBold"/>
                      <TextBlock TextWrapping="Wrap" x:Name="StoreResetStatus" Style="{StaticResource Muted}" Tag="Store bloqué ou téléchargements en échec : cache local de l&apos;utilisateur vidé" Text="Store bloqué ou téléchargements en échec : cache local de l&apos;utilisateur vidé"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                      <TextBlock x:Name="StoreResetLast" Style="{StaticResource Muted}" FontSize="11" TextAlignment="Right" TextWrapping="NoWrap" VerticalAlignment="Center" Margin="0,0,12,0"/>
                      <Button x:Name="StoreResetBtn" Content="Vider le cache" Style="{StaticResource WarnBtn}" MinWidth="96"/>
                    </StackPanel>
                  </Grid>
                </Border>
                <Border Style="{StaticResource HoverPlain}">
                  <Grid Margin="8,4">
                    <StackPanel VerticalAlignment="Center" Margin="0,0,250,0">
                      <TextBlock TextWrapping="Wrap" Text="Pilote graphique" FontWeight="SemiBold"/>
                      <TextBlock TextWrapping="Wrap" x:Name="GpuResetStatus" Style="{StaticResource Muted}" Tag="Écran figé, artefacts ou scintillement : pilote de la carte graphique redémarré" Text="Écran figé, artefacts ou scintillement : pilote de la carte graphique redémarré"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                      <TextBlock x:Name="GpuResetLast" Style="{StaticResource Muted}" FontSize="11" TextAlignment="Right" TextWrapping="NoWrap" VerticalAlignment="Center" Margin="0,0,12,0"/>
                      <Button x:Name="GpuResetBtn" Content="Redémarrer" Style="{StaticResource WarnBtn}" MinWidth="96"/>
                    </StackPanel>
                  </Grid>
                </Border>
                <Border Style="{StaticResource HoverPlain}">
                  <Grid Margin="8,4">
                    <StackPanel VerticalAlignment="Center" Margin="0,0,250,0">
                      <TextBlock TextWrapping="Wrap" Text="Réinitialisation réseau" FontWeight="SemiBold"/>
                      <TextBlock TextWrapping="Wrap" x:Name="NetResetStatus" Style="{StaticResource Muted}" Tag="Connexion ou résolution DNS en échec : cache DNS vidé et Winsock réinitialisé (redémarrage requis)" Text="Connexion ou résolution DNS en échec : cache DNS vidé et Winsock réinitialisé (redémarrage requis)"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                      <TextBlock x:Name="NetResetLast" Style="{StaticResource Muted}" FontSize="11" TextAlignment="Right" TextWrapping="NoWrap" VerticalAlignment="Center" Margin="0,0,12,0"/>
                      <Button x:Name="NetResetBtn" Content="Réinitialiser" Style="{StaticResource WarnBtn}" MinWidth="96"/>
                    </StackPanel>
                  </Grid>
                </Border>
                <Border Style="{StaticResource HoverPlain}">
                  <Grid Margin="8,4">
                    <StackPanel VerticalAlignment="Center" Margin="0,0,250,0">
                      <TextBlock TextWrapping="Wrap" Text="Spouleur d&apos;impression" FontWeight="SemiBold"/>
                      <TextBlock TextWrapping="Wrap" x:Name="SpoolResetStatus" Style="{StaticResource Muted}" Tag="Impressions bloquées : file d&apos;attente vidée et service redémarré" Text="Impressions bloquées : file d&apos;attente vidée et service redémarré"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                      <TextBlock x:Name="SpoolResetLast" Style="{StaticResource Muted}" FontSize="11" TextAlignment="Right" TextWrapping="NoWrap" VerticalAlignment="Center" Margin="0,0,12,0"/>
                      <Button x:Name="SpoolResetBtn" Content="Purger" Style="{StaticResource WarnBtn}" MinWidth="96"/>
                    </StackPanel>
                  </Grid>
                </Border>
                <Border Style="{StaticResource HoverPlain}">
                  <Grid Margin="8,4">
                    <StackPanel VerticalAlignment="Center" Margin="0,0,250,0">
                      <TextBlock TextWrapping="Wrap" Text="Heure du poste" FontWeight="SemiBold"/>
                      <TextBlock TextWrapping="Wrap" x:Name="TimeSyncStatus" Style="{StaticResource Muted}" Tag="Heure décalée, erreurs de certificat ou d&apos;ouverture de session : heure resynchronisée sur le serveur de temps" Text="Heure décalée, erreurs de certificat ou d&apos;ouverture de session : heure resynchronisée sur le serveur de temps"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                      <TextBlock x:Name="TimeSyncLast" Style="{StaticResource Muted}" FontSize="11" TextAlignment="Right" TextWrapping="NoWrap" VerticalAlignment="Center" Margin="0,0,12,0"/>
                      <Button x:Name="TimeSyncBtn" Content="Synchroniser" Style="{StaticResource ActionBtn}" MinWidth="96"/>
                    </StackPanel>
                  </Grid>
                </Border>
                <Border Style="{StaticResource HoverPlain}">
                  <Grid Margin="8,4">
                    <StackPanel VerticalAlignment="Center" Margin="0,0,250,0">
                      <TextBlock TextWrapping="Wrap" Text="Stratégies de groupe" FontWeight="SemiBold"/>
                      <TextBlock TextWrapping="Wrap" x:Name="GpForceStatus" Style="{StaticResource Muted}" Tag="GPO non appliquées ou récemment modifiées : toutes les stratégies ordinateur et utilisateur réappliquées" Text="GPO non appliquées ou récemment modifiées : toutes les stratégies ordinateur et utilisateur réappliquées"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                      <TextBlock x:Name="GpForceLast" Style="{StaticResource Muted}" FontSize="11" TextAlignment="Right" TextWrapping="NoWrap" VerticalAlignment="Center" Margin="0,0,12,0"/>
                      <Button x:Name="GpForceBtn" Content="Appliquer" Style="{StaticResource WarnBtn}" MinWidth="96"/>
                    </StackPanel>
                  </Grid>
                </Border>
                </StackPanel>
                </Border>
              </StackPanel>
            </ScrollViewer>
          </Border>
        </Grid>

        <!-- bandeau Point de restauration fixe en haut ; seules les cartes défilent dessous -->
        <Grid x:Name="PagePerf" Visibility="Collapsed">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <Border Grid.Row="0" Style="{StaticResource Panel}" Padding="16,6,16,6" Margin="0,0,0,10">
              <Grid>
                <DockPanel VerticalAlignment="Center" Margin="0,0,350,0">
                  <TextBlock Text="&#xE777;" Style="{StaticResource CardIcon}" DockPanel.Dock="Left" VerticalAlignment="Center"/>
                  <TextBlock Text="Point de restauration" Style="{StaticResource Section}" DockPanel.Dock="Left" VerticalAlignment="Center"/>
                  <TextBlock x:Name="RestoreDesc" TextWrapping="Wrap" Style="{StaticResource Muted}" Margin="14,0,0,0" VerticalAlignment="Center" Text="conseillé avant d&apos;appliquer des réglages (Checkpoint-Computer sur le lecteur système)"/>
                </DockPanel>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                  <TextBlock x:Name="RestoreLast" Style="{StaticResource Muted}" FontSize="11" TextAlignment="Right" TextWrapping="NoWrap" VerticalAlignment="Center" Margin="0,0,12,0" Text="..."/>
                  <Button x:Name="PersoRestore" Content="Créer" Style="{StaticResource ActionBtn}" MinWidth="96"/>
                  <Button x:Name="RestoreBack" Visibility="Collapsed" Content="Restaurer..." Style="{StaticResource ActionBtn}" MinWidth="96" Margin="8,0,0,0" ToolTip="Revenir à un point de restauration existant (redémarrage)"/>
                </StackPanel>
              </Grid>
            </Border>
            <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="12"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <StackPanel x:Name="PerfLeft" Grid.Column="0"/>
                <StackPanel x:Name="PerfRight" Grid.Column="2"/>
              </Grid>
            </ScrollViewer>
        </Grid>

        <Grid x:Name="PageSecu" Visibility="Collapsed">
          <ScrollViewer VerticalScrollBarVisibility="Auto">
            <Grid x:Name="SecuGrid">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="12"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="12"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
              </Grid.RowDefinitions>
              <StackPanel x:Name="SecuLeft" Grid.Column="0"/>
              <StackPanel x:Name="SecuMid" Grid.Column="2"/>
              <StackPanel x:Name="SecuRight" Grid.Column="4"/>
            </Grid>
          </ScrollViewer>
        </Grid>

        <Grid x:Name="PagePerso" Visibility="Collapsed">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="12"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <StackPanel x:Name="PersoLeft" Grid.Column="0"/>
              <StackPanel x:Name="PersoRight" Grid.Column="2"/>
            </Grid>
          </ScrollViewer>
        </Grid>

        <Grid x:Name="PageApps" Visibility="Collapsed">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <!-- 3 modes : installer des applications du catalogue / logiciels installés (désinstaller, réinstaller) / mettre à jour -->
          <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
            <Button x:Name="AppsModeInst" Style="{StaticResource ActionBtn}" Height="34" Padding="16,0" Margin="0,0,8,0">
              <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE896;" FontFamily="Segoe MDL2 Assets" FontSize="13" VerticalAlignment="Center" Margin="0,0,8,0"/><TextBlock Text="Installer" VerticalAlignment="Center"/></StackPanel>
            </Button>
            <Button x:Name="AppsModeMine" Style="{StaticResource ActionBtn}" Height="34" Padding="16,0" Margin="0,0,8,0" Tag="on">
              <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE8FD;" FontFamily="Segoe MDL2 Assets" FontSize="13" VerticalAlignment="Center" Margin="0,0,8,0"/><TextBlock x:Name="AppsModeMineTxt" Text="Mes applications" VerticalAlignment="Center"/></StackPanel>
            </Button>
            <Button x:Name="AppsModeUpd" Style="{StaticResource ActionBtn}" Height="34" Padding="16,0">
              <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE895;" FontFamily="Segoe MDL2 Assets" FontSize="13" VerticalAlignment="Center" Margin="0,0,8,0"/><TextBlock x:Name="AppsModeUpdTxt" Text="Mettre à jour" VerticalAlignment="Center"/></StackPanel>
            </Button>
          </StackPanel>
          <Grid x:Name="AppsInstView" Grid.Row="1" Visibility="Collapsed">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <Border Style="{StaticResource Panel}" Padding="18,14" Margin="0,0,0,10">
              <StackPanel>
                <DockPanel LastChildFill="True">
                  <Button x:Name="AppsInstall" DockPanel.Dock="Right" Style="{StaticResource PrimaryBtn}" Height="36" MinWidth="200" Padding="16,0" FontSize="14" Content="Installer la sélection" IsEnabled="False"/>
                  <Button x:Name="AppsPortable" DockPanel.Dock="Right" Style="{StaticResource ActionBtn}" Height="36" Padding="14,0" Margin="0,0,8,0" FontSize="14" Content="Ouvrir en portable" Visibility="Collapsed"/>
                  <Button x:Name="AppsClear" DockPanel.Dock="Right" Style="{StaticResource ActionBtn}" Height="36" Padding="14,0" Margin="0,0,8,0" Content="Tout désélectionner" Visibility="Collapsed"/>
                  <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock Text="&#xE71D;" FontFamily="Segoe MDL2 Assets" FontSize="22" VerticalAlignment="Center" Foreground="{DynamicResource AccentBrush}" Margin="0,0,12,0"/>
                    <StackPanel VerticalAlignment="Center">
                      <TextBlock Text="Installer des applications" FontSize="18" FontWeight="SemiBold"/>
                      <TextBlock x:Name="AppsStatus" FontSize="12.5" Foreground="{DynamicResource MutedBrush}" TextWrapping="Wrap" Margin="0,2,0,0"/>
                    </StackPanel>
                  </StackPanel>
                </DockPanel>
                <DockPanel Margin="0,14,0,0">
                  <Border x:Name="AppsFindBox" DockPanel.Dock="Left" Width="260" Height="34" CornerRadius="17" BorderThickness="1" Margin="0,0,12,0" VerticalAlignment="Top" BorderBrush="{DynamicResource LineBrush}" Background="{DynamicResource BgBrush}">
                    <Grid Margin="12,0">
                      <TextBlock Text="&#xE721;" FontFamily="Segoe MDL2 Assets" FontSize="13" VerticalAlignment="Center" Foreground="{DynamicResource MutedBrush}" IsHitTestVisible="False"/>
                      <TextBlock x:Name="AppsFindHint" Text="Rechercher une application" Margin="22,0,0,0" VerticalAlignment="Center" Foreground="{DynamicResource MutedBrush}" IsHitTestVisible="False"/>
                      <TextBox x:Name="AppsFind" Margin="20,0,0,0" VerticalAlignment="Center" BorderThickness="0" Background="Transparent" Foreground="{DynamicResource FgBrush}" CaretBrush="{DynamicResource FgBrush}"/>
                    </Grid>
                  </Border>
                  <WrapPanel x:Name="AppsChips" VerticalAlignment="Center"/>
                </DockPanel>
              </StackPanel>
            </Border>
            <ScrollViewer x:Name="AppsScroll" Grid.Row="1" VerticalScrollBarVisibility="Auto">
              <StackPanel x:Name="AppsPanel" Margin="0,0,4,8"/>
            </ScrollViewer>
          </Grid>
          <Grid x:Name="AppsUpdHost" Grid.Row="1" Visibility="Collapsed"/>
        </Grid>

        <!-- Services Windows : tiers / Microsoft (éditeur du fichier du service), démarrer, arrêter, désactiver à l'unité -->
        <!-- Services et tâches planifiées : 2 vues de même présentation, choisies par les boutons du haut -->
        <Grid x:Name="PageSvc" Visibility="Collapsed">
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
            <Button x:Name="SvcModeSvc" Style="{StaticResource ActionBtn}" Height="34" Padding="16,0" Margin="0,0,8,0" Tag="on">
              <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE912;" FontFamily="Segoe MDL2 Assets" FontSize="13" VerticalAlignment="Center" Margin="0,0,8,0"/><TextBlock Text="Services" VerticalAlignment="Center"/></StackPanel>
            </Button>
            <Button x:Name="SvcModeTsk" Style="{StaticResource ActionBtn}" Height="34" Padding="16,0">
              <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE823;" FontFamily="Segoe MDL2 Assets" FontSize="13" VerticalAlignment="Center" Margin="0,0,8,0"/><TextBlock Text="Tâches planifiées" VerticalAlignment="Center"/></StackPanel>
            </Button>
          </StackPanel>
          <Grid x:Name="SvcView" Grid.Row="1">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
              <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <DockPanel Margin="0,0,0,10">
              <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
                <Border x:Name="SvcFindBox" Width="240" Height="34" CornerRadius="17" Background="{DynamicResource BgBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1.5" VerticalAlignment="Center" Cursor="IBeam">
                  <Grid>
                    <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                    <TextBlock Text="&#xE721;" FontFamily="Segoe MDL2 Assets" FontSize="12" Foreground="{DynamicResource AccentBrush}" Margin="12,0,8,0" VerticalAlignment="Center"/>
                    <TextBox x:Name="SvcFind" Grid.Column="1" BorderThickness="0" Background="Transparent" Foreground="{DynamicResource FgBrush}" CaretBrush="{DynamicResource FgBrush}" VerticalAlignment="Center" Margin="0,0,12,0" FontSize="13">
                      <TextBox.Template><ControlTemplate TargetType="TextBox"><ScrollViewer x:Name="PART_ContentHost" Focusable="False" HorizontalScrollBarVisibility="Hidden" VerticalScrollBarVisibility="Hidden" Background="Transparent"/></ControlTemplate></TextBox.Template>
                    </TextBox>
                    <TextBlock x:Name="SvcFindHint" Grid.Column="1" Text="Filtrer les services" Foreground="{DynamicResource MutedBrush}" VerticalAlignment="Center" IsHitTestVisible="False"/>
                  </Grid>
                </Border>
                <Button x:Name="SvcRefresh" Style="{StaticResource ActionBtn}" Height="34" Padding="14,0" Margin="8,0,0,0" ToolTip="Relire l'état des services (F5)">
                  <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE72C;" FontFamily="Segoe MDL2 Assets" FontSize="13" VerticalAlignment="Center" Margin="0,0,8,0"/><TextBlock Text="Actualiser" VerticalAlignment="Center"/></StackPanel>
                </Button>
              </StackPanel>
              <WrapPanel VerticalAlignment="Center">
                <Button x:Name="SvcFOther" Style="{StaticResource ActionBtn}" Height="34" Padding="14,0" Margin="0,0,8,0" Content="Autres éditeurs"
                        ToolTip="Services installés par les logiciels et pilotes (éditeur du fichier du service autre que Microsoft)"/>
                <Button x:Name="SvcFMs" Style="{StaticResource ActionBtn}" Height="34" Padding="14,0" Margin="0,0,8,0" Content="Microsoft"
                        ToolTip="Services de Windows et des logiciels Microsoft (éditeur du fichier du service : Microsoft)"/>
                <Button x:Name="SvcFAll" Style="{StaticResource ActionBtn}" Height="34" Padding="14,0" Margin="0,0,16,0" Tag="on" Content="Tous"/>
                <Button x:Name="SvcFRun" Style="{StaticResource ActionBtn}" Height="34" Padding="14,0" Content="En cours uniquement"
                        ToolTip="Afficher seulement les services démarrés"/>
              </WrapPanel>
            </DockPanel>
            <Border Grid.Row="1" Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="6">
              <Grid>
                <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
                <Grid x:Name="SvcHead" Margin="14,8,28,6">
                  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="120"/><ColumnDefinition Width="160"/><ColumnDefinition Width="190"/><ColumnDefinition Width="206"/></Grid.ColumnDefinitions>
                  <TextBlock Text="SERVICE" Foreground="{DynamicResource MutedBrush}" FontSize="11" FontWeight="SemiBold"/>
                  <TextBlock Grid.Column="1" Text="ÉTAT" Foreground="{DynamicResource MutedBrush}" FontSize="11" FontWeight="SemiBold"/>
                  <TextBlock Grid.Column="2" Text="DÉMARRAGE" Foreground="{DynamicResource MutedBrush}" FontSize="11" FontWeight="SemiBold"/>
                  <TextBlock Grid.Column="3" Text="ÉDITEUR" Foreground="{DynamicResource MutedBrush}" FontSize="11" FontWeight="SemiBold"/>
                </Grid>
                <Border Grid.Row="1" Height="1" VerticalAlignment="Top" Background="{DynamicResource LineBrush}"/>
                <ScrollViewer x:Name="SvcScroll" Grid.Row="1" VerticalScrollBarVisibility="Visible" Focusable="False"><StackPanel x:Name="SvcList" Margin="4"/></ScrollViewer>
                <TextBlock x:Name="SvcEmpty" Grid.Row="1" HorizontalAlignment="Center" VerticalAlignment="Center" Foreground="{DynamicResource MutedBrush}" FontSize="14" TextWrapping="Wrap" TextAlignment="Center" MaxWidth="460" Text="Lecture des services..."/>
              </Grid>
            </Border>
            <DockPanel Grid.Row="2" Margin="0,10,0,0">
              <ProgressBar x:Name="SvcProg" DockPanel.Dock="Bottom" Height="4" Margin="0,6,0,0" IsIndeterminate="True" Visibility="Collapsed" Foreground="{DynamicResource AccentBrush}" Background="Transparent" BorderThickness="0"/>
              <TextBlock x:Name="SvcStatus" Foreground="{DynamicResource MutedBrush}" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
            </DockPanel>
          </Grid>
          <Grid x:Name="TskView" Grid.Row="1" Visibility="Collapsed">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
              <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <DockPanel Margin="0,0,0,10">
              <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
                <Border x:Name="TskFindBox" Width="240" Height="34" CornerRadius="17" Background="{DynamicResource BgBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1.5" VerticalAlignment="Center" Cursor="IBeam">
                  <Grid>
                    <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                    <TextBlock Text="&#xE721;" FontFamily="Segoe MDL2 Assets" FontSize="12" Foreground="{DynamicResource AccentBrush}" Margin="12,0,8,0" VerticalAlignment="Center"/>
                    <TextBox x:Name="TskFind" Grid.Column="1" BorderThickness="0" Background="Transparent" Foreground="{DynamicResource FgBrush}" CaretBrush="{DynamicResource FgBrush}" VerticalAlignment="Center" Margin="0,0,12,0" FontSize="13">
                      <TextBox.Template><ControlTemplate TargetType="TextBox"><ScrollViewer x:Name="PART_ContentHost" Focusable="False" HorizontalScrollBarVisibility="Hidden" VerticalScrollBarVisibility="Hidden" Background="Transparent"/></ControlTemplate></TextBox.Template>
                    </TextBox>
                    <TextBlock x:Name="TskFindHint" Grid.Column="1" Text="Filtrer les tâches" Foreground="{DynamicResource MutedBrush}" VerticalAlignment="Center" IsHitTestVisible="False"/>
                  </Grid>
                </Border>
                <Button x:Name="TskRefresh" Style="{StaticResource ActionBtn}" Height="34" Padding="14,0" Margin="8,0,0,0" ToolTip="Relire les tâches planifiées (F5)">
                  <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE72C;" FontFamily="Segoe MDL2 Assets" FontSize="13" VerticalAlignment="Center" Margin="0,0,8,0"/><TextBlock Text="Actualiser" VerticalAlignment="Center"/></StackPanel>
                </Button>
              </StackPanel>
              <WrapPanel VerticalAlignment="Center">
                <Button x:Name="TskFOther" Style="{StaticResource ActionBtn}" Height="34" Padding="14,0" Margin="0,0,8,0" Content="Autres éditeurs"
                        ToolTip="Tâches créées par les logiciels installés (hors dossier \Microsoft du Planificateur)"/>
                <Button x:Name="TskFMs" Style="{StaticResource ActionBtn}" Height="34" Padding="14,0" Margin="0,0,8,0" Content="Microsoft"
                        ToolTip="Tâches de Windows et des logiciels Microsoft (dossier \Microsoft du Planificateur)"/>
                <Button x:Name="TskFAll" Style="{StaticResource ActionBtn}" Height="34" Padding="14,0" Margin="0,0,16,0" Tag="on" Content="Tous"/>
                <Button x:Name="TskFRun" Style="{StaticResource ActionBtn}" Height="34" Padding="14,0" Content="Activées uniquement"
                        ToolTip="Masquer les tâches désactivées"/>
              </WrapPanel>
            </DockPanel>
            <Border Grid.Row="1" Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="6">
              <Grid>
                <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
                <Grid x:Name="TskHead" Margin="14,8,28,6">
                  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="120"/><ColumnDefinition Width="160"/><ColumnDefinition Width="190"/><ColumnDefinition Width="206"/></Grid.ColumnDefinitions>
                  <TextBlock Text="TÂCHE" Foreground="{DynamicResource MutedBrush}" FontSize="11" FontWeight="SemiBold"/>
                  <TextBlock Grid.Column="1" Text="ÉTAT" Foreground="{DynamicResource MutedBrush}" FontSize="11" FontWeight="SemiBold"/>
                  <TextBlock Grid.Column="2" Text="DERNIÈRE EXÉCUTION" Foreground="{DynamicResource MutedBrush}" FontSize="11" FontWeight="SemiBold"/>
                  <TextBlock Grid.Column="3" Text="PROCHAINE EXÉCUTION" Foreground="{DynamicResource MutedBrush}" FontSize="11" FontWeight="SemiBold"/>
                </Grid>
                <Border Grid.Row="1" Height="1" VerticalAlignment="Top" Background="{DynamicResource LineBrush}"/>
                <ScrollViewer x:Name="TskScroll" Grid.Row="1" VerticalScrollBarVisibility="Visible" Focusable="False"><StackPanel x:Name="TskList" Margin="4"/></ScrollViewer>
                <TextBlock x:Name="TskEmpty" Grid.Row="1" HorizontalAlignment="Center" VerticalAlignment="Center" Foreground="{DynamicResource MutedBrush}" FontSize="14" TextWrapping="Wrap" TextAlignment="Center" MaxWidth="460" Text="Lecture des tâches planifiées..."/>
              </Grid>
            </Border>
            <DockPanel Grid.Row="2" Margin="0,10,0,0">
              <ProgressBar x:Name="TskProg" DockPanel.Dock="Bottom" Height="4" Margin="0,6,0,0" IsIndeterminate="True" Visibility="Collapsed" Foreground="{DynamicResource AccentBrush}" Background="Transparent" BorderThickness="0"/>
              <TextBlock x:Name="TskStatus" Foreground="{DynamicResource MutedBrush}" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
            </DockPanel>
          </Grid>
        </Grid>

        <!-- Outils : licence, Wi-Fi, hosts, menu clic droit, variables d'environnement (cartes construites à la 1re ouverture) -->
        <ScrollViewer x:Name="PageTools" Visibility="Collapsed" VerticalScrollBarVisibility="Auto">
          <Grid Margin="0,0,6,0">
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="12"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <StackPanel x:Name="ToolsLeft"/>
            <StackPanel x:Name="ToolsRight" Grid.Column="2"/>
          </Grid>
        </ScrollViewer>

        <Grid x:Name="PageLog" Visibility="Collapsed">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <Border x:Name="RunPanel" Style="{StaticResource Panel}" Padding="16,12" Margin="0,0,0,10" Visibility="Collapsed">
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <StackPanel>
                <Grid>
                  <TextBlock x:Name="RunTitle" FontSize="15" FontWeight="SemiBold" TextWrapping="Wrap" Margin="0,0,90,0"/>
                  <TextBlock TextWrapping="Wrap" x:Name="RunPct" FontSize="15" FontWeight="SemiBold" HorizontalAlignment="Right" Foreground="{DynamicResource HeadBrush}"/>
                </Grid>
                <ProgressBar x:Name="RunBar" Height="10" Margin="0,8,0,6" Minimum="0" Maximum="100"
                             Foreground="{DynamicResource AccentBrush}" Background="{DynamicResource BgBrush}" BorderThickness="0"/>
                <TextBlock TextWrapping="Wrap" x:Name="RunInfo" Style="{StaticResource Muted}" FontSize="13"/>
              </StackPanel>
              <Button x:Name="AbortBtn" Grid.Column="1" Content="Interrompre" Style="{StaticResource ActionBtn}" Margin="16,0,0,0" VerticalAlignment="Center"/>
            </Grid>
          </Border>
          <Border Grid.Row="1" Style="{StaticResource Panel}" Padding="16,12" Margin="0,0,0,10">
            <DockPanel>
              <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
                <Button x:Name="ReportBtn" Content="Rapport d'intervention" Style="{StaticResource PrimaryBtn}" Margin="0,0,8,0" ToolTip="Rapport de la session : poste, état, actions réalisées, mises à jour, points d'attention (page web imprimable en PDF)"/>
                <Button x:Name="OpenLogDir" Content="Dossier des journaux" Style="{StaticResource ActionBtn}" Margin="0,0,8,0"/>
                <Border Width="1" Height="22" Margin="4,0,12,0" Background="{DynamicResource LineBrush}" VerticalAlignment="Center"/>
                <Button x:Name="LogPurgeOld" Content="Supprimer les plus de 30 jours" Style="{StaticResource ActionBtn}" Margin="0,0,8,0"/>
                <Button x:Name="LogPurgeAll" Content="Tout supprimer" Style="{StaticResource WarnBtn}"/>
              </StackPanel>
              <StackPanel VerticalAlignment="Center" Margin="0,0,16,0">
                <DockPanel><TextBlock Text="&#xE81C;" Style="{StaticResource CardIcon}" DockPanel.Dock="Left"/><TextBlock Text="Journal de la session" Style="{StaticResource Section}"/></DockPanel>
                <TextBlock x:Name="LogStats" Style="{StaticResource Muted}" Margin="30,2,0,0" TextWrapping="Wrap"/>
              </StackPanel>
            </DockPanel>
          </Border>
          <!-- filtre du journal : niveau (tout / erreurs / avertissements et erreurs) et texte -->
          <DockPanel Grid.Row="2" Margin="0,0,0,8">
            <StackPanel Orientation="Horizontal" DockPanel.Dock="Left" VerticalAlignment="Center">
              <Button x:Name="LogFAll" Style="{StaticResource ActionBtn}" Height="30" Padding="12,0" Margin="0,0,6,0" Tag="on" Content="Tout"/>
              <Button x:Name="LogFWarn" Style="{StaticResource ActionBtn}" Height="30" Padding="12,0" Margin="0,0,6,0" Content="Avertissements"/>
              <Button x:Name="LogFErr" Style="{StaticResource ActionBtn}" Height="30" Padding="12,0" Margin="0,0,6,0" Content="Erreurs"/>
              <CheckBox x:Name="LogFApp" Style="{StaticResource TaskCheck}" Content="Messages de l'application" IsChecked="True" Margin="14,0,0,0" VerticalAlignment="Center"
                        ToolTip="Démarrage, affichage, paramètres de l'application, actualisations : décocher pour ne garder que les actions sur le poste"/>
              <!-- zoom du texte du journal : à gauche de la barre, donc jamais masqué quelle que soit la largeur de la fenêtre -->
              <Border Margin="18,0,0,0" Height="30" Padding="2,0" CornerRadius="6" Background="{DynamicResource BgBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" VerticalAlignment="Center"
                      ToolTip="Taille du texte du journal (70 à 200 %) : Ctrl + molette ou Ctrl + / Ctrl - sur la zone, clic sur le pourcentage ou Ctrl + 0 pour revenir à 100 %">
                <StackPanel Orientation="Horizontal">
                  <Button x:Name="LogZoomOut" Style="{StaticResource IconBtn}" Width="28" Height="26" FontSize="12" Content="&#xE71F;"/>
                  <TextBlock x:Name="LogZoomTxt" Style="{StaticResource Muted}" FontSize="12" Width="44" TextAlignment="Center" VerticalAlignment="Center" Cursor="Hand" Text="100 %"/>
                  <Button x:Name="LogZoomIn" Style="{StaticResource IconBtn}" Width="28" Height="26" FontSize="12" Content="&#xE8A3;"/>
                </StackPanel>
              </Border>
            </StackPanel>
            <Border x:Name="LogFindBox" DockPanel.Dock="Right" Width="300" Height="30" CornerRadius="15" Background="{DynamicResource BgBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1.5" VerticalAlignment="Center" Cursor="IBeam">
              <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <TextBlock Text="&#xE721;" FontFamily="Segoe MDL2 Assets" FontSize="12" Foreground="{DynamicResource AccentBrush}" Margin="12,0,8,0" VerticalAlignment="Center"/>
                <TextBox x:Name="LogFind" Grid.Column="1" BorderThickness="0" Background="Transparent" Foreground="{DynamicResource FgBrush}" CaretBrush="{DynamicResource FgBrush}" VerticalAlignment="Center" Margin="0,0,12,0" FontSize="13">
                  <TextBox.Template><ControlTemplate TargetType="TextBox"><ScrollViewer x:Name="PART_ContentHost" Focusable="False" HorizontalScrollBarVisibility="Hidden" VerticalScrollBarVisibility="Hidden" Background="Transparent"/></ControlTemplate></TextBox.Template>
                </TextBox>
                <TextBlock x:Name="LogFindHint" Grid.Column="1" Text="Rechercher dans le journal" Foreground="{DynamicResource MutedBrush}" VerticalAlignment="Center" IsHitTestVisible="False"/>
              </Grid>
            </Border>
            <TextBlock x:Name="LogFilterInfo" Style="{StaticResource Muted}" FontSize="12" VerticalAlignment="Center" Margin="12,0,12,0" TextTrimming="CharacterEllipsis"/>
          </DockPanel>
          <!-- lignes colorées par niveau (heure, niveau, message) ; sélection et copie possibles -->
          <Border Grid.Row="3" Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="8">
            <Grid>
              <RichTextBox x:Name="LogBox" IsReadOnly="True" IsReadOnlyCaretVisible="False" BorderThickness="0" Background="Transparent" Foreground="{DynamicResource FgBrush}"
                           FontFamily="Segoe UI" FontSize="13" Padding="12,10" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"
                           SelectionBrush="{DynamicResource SelBrush}" CaretBrush="{DynamicResource FgBrush}">
                <FlowDocument PagePadding="0" FontFamily="Segoe UI" FontSize="13"/>
              </RichTextBox>
              <TextBlock x:Name="LogEmpty" Style="{StaticResource Muted}" FontSize="13" HorizontalAlignment="Center" VerticalAlignment="Center" TextAlignment="Center" Visibility="Collapsed" IsHitTestVisible="False"/>
            </Grid>
          </Border>
        </Grid>

        <ScrollViewer x:Name="PageSettings" Visibility="Collapsed" VerticalScrollBarVisibility="Auto">
          <StackPanel x:Name="SettingsPanel" MaxWidth="1400" HorizontalAlignment="Stretch"/>
        </ScrollViewer>

        <Grid x:Name="PageInfo">
          <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <ScrollViewer VerticalScrollBarVisibility="Auto">
           <StackPanel>
            <!-- moniteur d'activité : 3 tuiles alignées sur les 3 colonnes de cartes -->
            <Grid x:Name="ActGrid">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="12"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="12"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
            </Grid>
            <Grid x:Name="InfoGrid">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="12"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="12"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
              </Grid.RowDefinitions>
              <StackPanel x:Name="InfoLeft" Grid.Column="0"/>
              <StackPanel x:Name="InfoMid" Grid.Column="2"/>
              <StackPanel x:Name="InfoRight" Grid.Column="4"/>
            </Grid>
           </StackPanel>
          </ScrollViewer>
        </Grid>
      </Grid>

      <Grid x:Name="Footer" Grid.Row="5" Background="{DynamicResource PanelBrush}" MinHeight="58">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <Button x:Name="RunBtn" Grid.Column="0" Content="Appliquer la sélection" Style="{StaticResource PrimaryBtn}" MinWidth="220" Margin="14,10,8,10" IsEnabled="False"/>
        <Button x:Name="StopBtn" Grid.Column="2" Content="Interrompre" Style="{StaticResource ActionBtn}" Margin="0,10,8,10" IsEnabled="False"/>
        <CheckBox x:Name="AutoReboot" Grid.Column="3" Style="{StaticResource TaskCheck}" Content="Redémarrer à la fin si nécessaire" VerticalAlignment="Center" Margin="8,0,8,0" Visibility="Collapsed"
                  ToolTip="Si une tâche demande un redémarrage (mises à jour, réinitialisation réseau...), le poste redémarre 2 minutes après la fin, sans question. Annulable dans la carte Mises à jour Windows."/>
        <Border Grid.ColumnSpan="6" Height="1" VerticalAlignment="Top" Background="{DynamicResource LineBrush}"/>
        <StackPanel x:Name="FooterStatus" Grid.Column="4" VerticalAlignment="Center" Margin="10,12,16,12">
          <TextBlock x:Name="StatusText" Text="Prêt" Foreground="{DynamicResource MutedBrush}" TextWrapping="Wrap"/>
          <ProgressBar x:Name="ProgressBar" Height="6" Margin="0,6,0,0" Minimum="0" Maximum="100" Value="0"
                       Foreground="{DynamicResource AccentBrush}" Background="{DynamicResource BgBrush}" BorderThickness="0"/>
        </StackPanel>
        <Button x:Name="FooterClose" Grid.Column="5" Content="&#xE711;" Style="{StaticResource IconBtn}" Width="32" Height="30" Margin="0,0,12,0" ToolTip="Fermer" Visibility="Collapsed"/>
      </Grid>
    </Grid>
  </Border>
</Window>
'@

