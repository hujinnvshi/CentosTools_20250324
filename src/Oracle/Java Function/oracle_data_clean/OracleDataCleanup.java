package oracle.data.cleanup;

import java.awt.BorderLayout;
import java.awt.Color;
import java.awt.Component;
import java.awt.Dimension;
import java.awt.FlowLayout;
import java.awt.Font;
import java.awt.GridBagConstraints;
import java.awt.GridBagLayout;
import java.awt.Insets;
import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.sql.CallableStatement;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.sql.Timestamp;
import java.sql.Types;
import java.text.DecimalFormat;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Properties;

import javax.swing.BorderFactory;
import javax.swing.Box;
import javax.swing.BoxLayout;
import javax.swing.DefaultListModel;
import javax.swing.JButton;
import javax.swing.JCheckBox;
import javax.swing.JComboBox;
import javax.swing.JFrame;
import javax.swing.JLabel;
import javax.swing.JList;
import javax.swing.JOptionPane;
import javax.swing.JPanel;
import javax.swing.JPasswordField;
import javax.swing.JProgressBar;
import javax.swing.JScrollPane;
import javax.swing.JSpinner;
import javax.swing.JTabbedPane;
import javax.swing.JTable;
import javax.swing.JTextArea;
import javax.swing.JTextField;
import javax.swing.ListSelectionModel;
import javax.swing.SpinnerNumberModel;
import javax.swing.SwingUtilities;
import javax.swing.SwingWorker;
import javax.swing.UIManager;
import javax.swing.border.EmptyBorder;
import javax.swing.border.TitledBorder;
import javax.swing.table.DefaultTableCellRenderer;
import javax.swing.table.DefaultTableModel;

/**
 * Oracle数据库垃圾数据清理工具
 * 提供图形化界面来管理Oracle数据库垃圾数据的识别和清理
 */
public class OracleDataCleanup extends JFrame {
    private static final long serialVersionUID = 1L;
    
    // 数据库连接信息
    private String jdbcUrl;
    private String username;
    private String password;
    private Connection connection;
    
    // UI组件
    private JTabbedPane tabbedPane;
    private JPanel connectionPanel;
    private JPanel dashboardPanel;
    private JPanel candidatesPanel;
    private JPanel configPanel;
    private JPanel reportPanel;
    
    // 连接面板组件
    private JTextField hostField;
    private JTextField portField;
    private JTextField sidField;
    private JTextField usernameField;
    private JPasswordField passwordField;
    private JButton connectButton;
    private JLabel statusLabel;
    
    // 仪表盘面板组件
    private JLabel dbNameLabel;
    private JLabel dbSizeLabel;
    private JLabel lastCleanupLabel;
    private JLabel spaceSavedLabel;
    private JButton runAnalysisButton;
    private JCheckBox autoApproveCheckbox;
    private JProgressBar progressBar;
    
    // 候选面板组件
    private DefaultTableModel candidatesTableModel;
    private JTable candidatesTable;
    private JButton approveButton;
    private JButton rejectButton;
    private JButton executeCleanupButton;
    private JButton refreshCandidatesButton;
    
    // 配置面板组件
    private DefaultTableModel configTableModel;
    private JTable configTable;
    private JButton saveConfigButton;
    
    // 报告面板组件
    private JSpinner daysBackSpinner;
    private JButton generateReportButton;
    private JTextArea reportTextArea;
    
    /**
     * 构造函数
     */
    public OracleDataCleanup() {
        setTitle("Oracle数据库垃圾数据清理工具");
        setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
        setSize(900, 600);
        setLocationRelativeTo(null);
        
        try {
            // 设置系统外观
            UIManager.setLookAndFeel(UIManager.getSystemLookAndFeelClassName());
        } catch (Exception e) {
            e.printStackTrace();
        }
        
        // 初始化UI组件
        initComponents();
        
        // 布局UI组件
        layoutComponents();
        
        // 添加事件监听器
        addEventListeners();
    }
    
    /**
     * 初始化UI组件
     */
    private void initComponents() {
        // 创建选项卡面板
        tabbedPane = new JTabbedPane();
        
        // 初始化各个面板
        connectionPanel = new JPanel();
        dashboardPanel = new JPanel();
        candidatesPanel = new JPanel();
        configPanel = new JPanel();
        reportPanel = new JPanel();
        
        // 初始化连接面板组件
        hostField = new JTextField("localhost", 15);
        portField = new JTextField("1521", 5);
        sidField = new JTextField("ORCL", 10);
        usernameField = new JTextField("system", 15);
        passwordField = new JPasswordField(15);
        connectButton = new JButton("连接数据库");
        statusLabel = new JLabel("未连接");
        statusLabel.setForeground(Color.RED);
        
        // 初始化仪表盘面板组件
        dbNameLabel = new JLabel("数据库: 未连接");
        dbSizeLabel = new JLabel("数据库大小: 未知");
        lastCleanupLabel = new JLabel("上次清理时间: 未知");
        spaceSavedLabel = new JLabel("已节省空间: 0 MB");
        runAnalysisButton = new JButton("运行分析");
        autoApproveCheckbox = new JCheckBox("自动批准清理候选");
        progressBar = new JProgressBar();
        progressBar.setStringPainted(true);
        
        // 初始化候选面板组件
        String[] candidatesColumns = {"ID", "类型", "所有者", "名称", "原因", "识别时间", "状态"};
        candidatesTableModel = new DefaultTableModel(candidatesColumns, 0) {
            private static final long serialVersionUID = 1L;
            @Override
            public boolean isCellEditable(int row, int column) {
                return false; // 表格不可编辑
            }
        };
        candidatesTable = new JTable(candidatesTableModel);
        candidatesTable.setSelectionMode(ListSelectionModel.MULTIPLE_INTERVAL_SELECTION);
        candidatesTable.getTableHeader().setReorderingAllowed(false);
        
        approveButton = new JButton("批准选中项");
        rejectButton = new JButton("拒绝选中项");
        executeCleanupButton = new JButton("执行已批准的清理");
        refreshCandidatesButton = new JButton("刷新列表");
        
        // 初始化配置面板组件
        String[] configColumns = {"配置名称", "配置值", "描述"};
        configTableModel = new DefaultTableModel(configColumns, 0) {
            private static final long serialVersionUID = 1L;
            @Override
            public boolean isCellEditable(int row, int column) {
                return column == 1; // 只有配置值列可编辑
            }
        };
        configTable = new JTable(configTableModel);
        saveConfigButton = new JButton("保存配置");
        
        // 初始化报告面板组件
        daysBackSpinner = new JSpinner(new SpinnerNumberModel(30, 1, 365, 1));
        generateReportButton = new JButton("生成报告");
        reportTextArea = new JTextArea();
        reportTextArea.setEditable(false);
        reportTextArea.setFont(new Font(Font.MONOSPACED, Font.PLAIN, 12));
    }
    
    /**
     * 布局UI组件
     */
    private void layoutComponents() {
        // 设置主布局
        setLayout(new BorderLayout());
        add(tabbedPane, BorderLayout.CENTER);
        
        // 布局连接面板
        connectionPanel.setLayout(new GridBagLayout());
        GridBagConstraints gbc = new GridBagConstraints();
        gbc.insets = new Insets(5, 5, 5, 5);
        gbc.anchor = GridBagConstraints.WEST;
        
        gbc.gridx = 0; gbc.gridy = 0;
        connectionPanel.add(new JLabel("主机:"), gbc);
        gbc.gridx = 1;
        connectionPanel.add(hostField, gbc);
        
        gbc.gridx = 0; gbc.gridy = 1;
        connectionPanel.add(new JLabel("端口:"), gbc);
        gbc.gridx = 1;
        connectionPanel.add(portField, gbc);
        
        gbc.gridx = 0; gbc.gridy = 2;
        connectionPanel.add(new JLabel("SID:"), gbc);
        gbc.gridx = 1;
        connectionPanel.add(sidField, gbc);
        
        gbc.gridx = 0; gbc.gridy = 3;
        connectionPanel.add(new JLabel("用户名:"), gbc);
        gbc.gridx = 1;
        connectionPanel.add(usernameField, gbc);
        
        gbc.gridx = 0; gbc.gridy = 4;
        connectionPanel.add(new JLabel("密码:"), gbc);
        gbc.gridx = 1;
        connectionPanel.add(passwordField, gbc);
        
        gbc.gridx = 0; gbc.gridy = 5;
        gbc.gridwidth = 2;
        gbc.anchor = GridBagConstraints.CENTER;
        JPanel buttonPanel = new JPanel(new FlowLayout(FlowLayout.CENTER));
        buttonPanel.add(connectButton);
        buttonPanel.add(statusLabel);
        connectionPanel.add(buttonPanel, gbc);
        
        // 布局仪表盘面板
        dashboardPanel.setLayout(new BorderLayout());
        
        JPanel statsPanel = new JPanel();
        statsPanel.setLayout(new BoxLayout(statsPanel, BoxLayout.Y_AXIS));
        statsPanel.setBorder(BorderFactory.createTitledBorder("数据库统计"));
        statsPanel.add(dbNameLabel);
        statsPanel.add(Box.createVerticalStrut(10));
        statsPanel.add(dbSizeLabel);
        statsPanel.add(Box.createVerticalStrut(10));
        statsPanel.add(lastCleanupLabel);
        statsPanel.add(Box.createVerticalStrut(10));
        statsPanel.add(spaceSavedLabel);
        
        JPanel actionPanel = new JPanel();
        actionPanel.setLayout(new BoxLayout(actionPanel, BoxLayout.Y_AXIS));
        actionPanel.setBorder(BorderFactory.createTitledBorder("操作"));
        
        JPanel runPanel = new JPanel(new FlowLayout(FlowLayout.LEFT));
        runPanel.add(runAnalysisButton);
        runPanel.add(autoApproveCheckbox);
        actionPanel.add(runPanel);
        actionPanel.add(Box.createVerticalStrut(10));
        actionPanel.add(progressBar);
        
        JPanel topPanel = new JPanel(new BorderLayout());
        topPanel.add(statsPanel, BorderLayout.WEST);
        topPanel.add(actionPanel, BorderLayout.CENTER);
        
        dashboardPanel.add(topPanel, BorderLayout.NORTH);
        
        // 布局候选面板
        candidatesPanel.setLayout(new BorderLayout());
        candidatesPanel.setBorder(new EmptyBorder(10, 10, 10, 10));
        
        JScrollPane candidatesScrollPane = new JScrollPane(candidatesTable);
        candidatesScrollPane.setPreferredSize(new Dimension(800, 400));
        candidatesPanel.add(candidatesScrollPane, BorderLayout.CENTER);
        
        JPanel candidatesButtonPanel = new JPanel(new FlowLayout(FlowLayout.CENTER));
        candidatesButtonPanel.add(approveButton);
        candidatesButtonPanel.add(rejectButton);
        candidatesButtonPanel.add(executeCleanupButton);
        candidatesButtonPanel.add(refreshCandidatesButton);
        candidatesPanel.add(candidatesButtonPanel, BorderLayout.SOUTH);
        
        // 布局配置面板
        configPanel.setLayout(new BorderLayout());
        configPanel.setBorder(new EmptyBorder(10, 10, 10, 10));
        
        JScrollPane configScrollPane = new JScrollPane(configTable);
        configPanel.add(configScrollPane, BorderLayout.CENTER);
        
        JPanel configButtonPanel = new JPanel(new FlowLayout(FlowLayout.CENTER));
        configButtonPanel.add(saveConfigButton);
        configPanel.add(configButtonPanel, BorderLayout.SOUTH);
        
        // 布局报告面板
        reportPanel.setLayout(new BorderLayout());
        reportPanel.setBorder(new EmptyBorder(10, 10, 10, 10));
        
        JPanel reportControlPanel = new JPanel(new FlowLayout(FlowLayout.LEFT));
        reportControlPanel.add(new JLabel("显示最近"));
        reportControlPanel.add(daysBackSpinner);
        reportControlPanel.add(new JLabel("天的报告"));
        reportControlPanel.add(generateReportButton);
        reportPanel.add(reportControlPanel, BorderLayout.NORTH);
        
        JScrollPane reportScrollPane = new JScrollPane(reportTextArea);
        reportPanel.add(reportScrollPane, BorderLayout.CENTER);
        
        // 添加面板到选项卡
        tabbedPane.addTab("连接", connectionPanel);
        tabbedPane.addTab("仪表盘", dashboardPanel);
        tabbedPane.addTab("清理候选", candidatesPanel);
        tabbedPane.addTab("配置", configPanel);
        tabbedPane.addTab("报告", reportPanel);
        
        // 初始时禁用除连接面板外的其他面板
        tabbedPane.setEnabledAt(1, false);
        tabbedPane.setEnabledAt(2, false);
        tabbedPane.setEnabledAt(3, false);
        tabbedPane.setEnabledAt(4, false);
    }
    
    /**
     * 添加事件监听器
     */
    private void addEventListeners() {
        // 连接按钮事件
        connectButton.addActionListener(new ActionListener() {
            @Override
            public void actionPerformed(ActionEvent e) {
                connectToDatabase();
            }
        });
        
        // 运行分析按钮事件
        runAnalysisButton.addActionListener(new ActionListener() {
            @Override
            public void actionPerformed(ActionEvent e) {
                runAnalysis();
            }
        });
        
        // 批准按钮事件
        approveButton.addActionListener(new ActionListener() {
            @Override
            public void actionPerformed(ActionEvent e) {
                approveSelectedCandidates();
            }
        });
        
        // 拒绝按钮事件
        rejectButton.addActionListener(new ActionListener() {
            @Override
            public void actionPerformed(ActionEvent e) {
                rejectSelectedCandidates();
            }
        });
        
        // 执行清理按钮事件
        executeCleanupButton.addActionListener(new ActionListener() {
            @Override
            public void actionPerformed(ActionEvent e) {
                executeCleanup();
            }
        });
        
        // 刷新候选按钮事件
        refreshCandidatesButton.addActionListener(new ActionListener() {
            @Override
            public void actionPerformed(ActionEvent e) {
                loadCandidates();
            }
        });
        
        // 保存配置按钮事件
        saveConfigButton.addActionListener(new ActionListener() {
            @Override
            public void actionPerformed(ActionEvent e) {
                saveConfig();
            }
        });
        
        // 生成报告按钮事件
        generateReportButton.addActionListener(new ActionListener() {
            @Override
            public void actionPerformed(ActionEvent e) {
                generateReport();
            }
        });
    }
    
    /**
     * 连接到数据库
     */
    private void connectToDatabase() {
        final String host = hostField.getText().trim();
        final String port = portField.getText().trim();
        final String sid = sidField.getText().trim();
        final String user = usernameField.getText().trim();
        final String pass = new String(passwordField.getPassword());
        
        // 验证输入
        if (host.isEmpty() || port.isEmpty() || sid.isEmpty() || user.isEmpty() || pass.isEmpty()) {
            JOptionPane.showMessageDialog(this, "请填写所有连接信息", "输入错误", JOptionPane.ERROR_MESSAGE);
            return;
        }
        
        // 构建JDBC URL
        jdbcUrl = "jdbc:oracle:thin:@" + host + ":" + port + ":" + sid;
        username = user;
        password = pass;
        
        // 禁用连接按钮，显示连接中状态
        connectButton.setEnabled(false);
        statusLabel.setText("连接中...");
        statusLabel.setForeground(Color.BLUE);
        
        // 在后台线程中连接数据库
        SwingWorker<Boolean, Void> worker = new SwingWorker<Boolean, Void>() {
            @Override
            protected Boolean doInBackground() throws Exception {
                try {
                    // 加载Oracle JDBC驱动
                    Class.forName("oracle.jdbc.driver.OracleDriver");
                    
                    // 连接数据库
                    connection = DriverManager.getConnection(jdbcUrl, username, password);
                    return true;
                } catch (Exception ex) {
                    ex.printStackTrace();
                    return false;
                }
            }
            
            @Override
            protected void done() {
                try {
                    boolean success = get();
                    if (success) {
                        // 连接成功
                        statusLabel.setText("已连接");
                        statusLabel.setForeground(Color.GREEN);
                        
                        // 启用其他选项卡
                        for (int i = 1; i < tabbedPane.getTabCount(); i++) {
                            tabbedPane.setEnabledAt(i, true);
                        }
                        
                        // 切换到仪表盘选项卡
                        tabbedPane.setSelectedIndex(1);
                        
                        // 加载数据库信息
                        loadDatabaseInfo();
                        
                        // 加载配置
                        loadConfig();
                        
                        // 加载候选
                        loadCandidates();
                    } else {
                        // 连接失败
                        statusLabel.setText("连接失败");
                        statusLabel.setForeground(Color.RED);
                        connectButton.setEnabled(true);
                        JOptionPane.showMessageDialog(OracleDataCleanup.this, 
                                "无法连接到数据库，请检查连接信息", "连接错误", JOptionPane.ERROR_MESSAGE);
                    }
                } catch (Exception ex) {
                    ex.printStackTrace();
                    statusLabel.setText("连接错误");
                    statusLabel.setForeground(Color.RED);
                    connectButton.setEnabled(true);
                    JOptionPane.showMessageDialog(OracleDataCleanup.this, 
                            "连接过程中发生错误: " + ex.getMessage(), "连接错误", JOptionPane.ERROR_MESSAGE);
                }
            }
        };
        
        worker.execute();
    }
    
    /**
     * 加载数据库信息
     */
    private void loadDatabaseInfo() {
        if (connection == null) return;
        
        SwingWorker<Void, Void> worker = new SwingWorker<Void, Void>() {
            private String dbName = "未知";
            private String dbSize = "未知";
            private String lastCleanup = "未知";
            private String spaceSaved = "0 MB";
            
            @Override
            protected Void doInBackground() throws Exception {
                try {
                    // 获取数据库名称
                    try (Statement stmt = connection.createStatement();
                         ResultSet rs = stmt.executeQuery("SELECT SYS_CONTEXT('USERENV', 'DB_NAME') FROM DUAL")) {
                        if (rs.next()) {
                            dbName = rs.getString(1);
                        }
                    }
                    
                    // 获取数据库大小
                    try (Statement stmt = connection.createStatement();
                         ResultSet rs = stmt.executeQuery(
                                 "SELECT ROUND(SUM(bytes)/1024/1024/1024, 2) FROM dba_data_files")) {
                        if (rs.next()) {
                            double sizeGB = rs.getDouble(1);
                            dbSize = new DecimalFormat("#,##0.00").format(sizeGB) + " GB";
                        }
                    }
                    
                    // 获取上次清理时间
                    try (Statement stmt = connection.createStatement();
                         ResultSet rs = stmt.executeQuery(
                                 "SELECT TO_CHAR(MAX(operation_time), 'YYYY-MM-DD HH24:MI:SS') " +
                                 "FROM cleanup_log WHERE operation_type = 'CLEANUP' AND status = 'COMPLETED'")) {
                        if (rs.next() && rs.getString(1) != null) {
                            lastCleanup = rs.getString(1);
                        }
                    } catch (SQLException e) {
                        // 表可能不存在，忽略错误
                    }
                    
                    // 获取已节省空间
                    try {
                        CallableStatement cstmt = connection.prepareCall("{? = call db_cleanup.get_space_savings}");
                        cstmt.registerOutParameter(1, Types.NUMERIC);
                        cstmt.execute();
                        double savedBytes = cstmt.getDouble(1);
                        double savedMB = savedBytes / 1024 / 1024;
                        spaceSaved = new DecimalFormat("#,##0.00").format(savedMB) + " MB";
                        cstmt.close();
                    } catch (SQLException e) {
                        // 函数可能不存在，忽略错误
                    }
                    
                } catch (Exception e) {
                    e.printStackTrace();
                }
                return null;
            }
            
            @Override
            protected void done() {
                dbNameLabel.setText("数据库: " + dbName);
                dbSizeLabel.setText("数据库大小: " + dbSize);
                lastCleanupLabel.setText("上次清理时间: " + lastCleanup);
                spaceSavedLabel.setText("已节省空间: " + spaceSaved);
            }
        };
        
        worker.execute();
    }
    
    /**
     * 加载配置
     */
    private void loadConfig() {
        if (connection == null) return;
        
        SwingWorker<List<Object[]>, Void> worker = new SwingWorker<List<Object[]>, Void>() {
            @Override
            protected List<Object[]> doInBackground() throws Exception {
                List<Object[]> configData = new ArrayList<>();
                try (Statement stmt = connection.createStatement();
                     ResultSet rs = stmt.executeQuery(
                             "SELECT config_name, config_value, description FROM cleanup_config ORDER BY config_id")) {
                    while (rs.next()) {
                        Object[] row = new Object[3];
                        row[0] = rs.getString("config_name");
                        row[1] = rs.getString("config_value");
                        row[2] = rs.getString("description");
                        configData.add(row);
                    }
                } catch (SQLException e) {
                    // 表可能不存在
                    e.printStackTrace();
                }
                return configData;
            }
            
            @Override
            protected void done() {
                try {
                    List<Object[]> configData = get();
                    // 清空表格
                    configTableModel.setRowCount(0);
                    // 添加数据
                    for (Object[] row : configData) {
                        configTableModel.addRow(row);
                    }
                } catch (Exception e) {
                    e.printStackTrace();
                }
            }
        };
        
        worker.execute();
    }
    
    /**
     * 加载候选
     */
    private void loadCandidates() {
        if (connection == null) return;
        
        SwingWorker<List<Object[]>, Void> worker = new SwingWorker<List<Object[]>, Void>() {
            @Override
            protected List<Object[]> doInBackground() throws Exception {
                List<Object[]> candidateData = new ArrayList<>();
                try (Statement stmt = connection.createStatement();
                     ResultSet rs = stmt.executeQuery(
                             "SELECT candidate_id, object_type, object_owner, object_name, " +
                             "reason, TO_CHAR(identified_time, 'YYYY-MM-DD HH24:MI:SS'), status " +
                             "FROM cleanup_candidates " +
                             "WHERE status IN ('PENDING', 'APPROVED') " +
                             "ORDER BY priority, identified_time")) {
                    while (rs.next()) {
                        Object[] row = new Object[7];
                        row[0] = rs.getInt(1);
                        row[1] = rs.getString(2);
                        row[2] = rs.getString(3);
                        row[3] = rs.getString(4);
                        row[4] = rs.getString(5);
                        row[5] = rs.getString(6);
                        row[6] = rs.getString(7);
                        candidateData.add(row);
                    }
                } catch (SQLException e) {
                    // 表可能不存在
                    e.printStackTrace();
                }
                return candidateData;
            }
            
            @Override
            protected void done() {
                try {
                    List<Object[]> candidateData = get();
                    // 清空表格
                    candidatesTableModel.setRowCount(0);
                    // 添加数据
                    for (Object[] row : candidateData) {
                        candidatesTableModel.addRow(row);
                    }
                    
                    // 设置状态列的颜色
                    candidatesTable.getColumnModel().getColumn(6).setCellRenderer(new DefaultTableCellRenderer() {
                        private static final long serialVersionUID = 1L;
                        @Override
                        public Component getTableCellRendererComponent(JTable table, Object value, boolean isSelected, boolean hasFocus, int row, int column) {
                            Component c = super.getTableCellRendererComponent(table, value, isSelected, hasFocus, row, column);
                            if (value != null) {
                                if ("APPROVED".equals(value.toString())) {
                                    c.setForeground(Color.GREEN.darker());
                                } else if ("PENDING".equals(value.toString())) {
                                    c.setForeground(Color.BLUE);
                                } else {
                                    c.setForeground(table.getForeground());
                                }
                            }
                            return c;
                        }
                    });
                } catch (Exception e) {
                    e.printStackTrace();
                }
            }
        };
        
        worker.execute();
    }
    
    /**
     * 保存配置
     */
    private void saveConfig() {
        if (connection == null) return;
        
        final int rowCount = configTableModel.getRowCount();
        if (rowCount == 0) return;
        
        SwingWorker<Boolean, Void> worker = new SwingWorker<Boolean, Void>() {
            @Override
            protected Boolean doInBackground() throws Exception {
                try {
                    connection.setAutoCommit(false);
                    
                    PreparedStatement pstmt = connection.prepareStatement(
                            "UPDATE cleanup_config SET config_value = ?, last_updated = SYSTIMESTAMP, " +
                            "updated_by = ? WHERE config_name = ?");
                    
                    for (int i = 0; i < rowCount; i++) {
                        String configName = (String) configTableModel.getValueAt(i, 0);
                        String configValue = (String) configTableModel.getValueAt(i, 1);
                        
                        pstmt.setString(1, configValue);
                        pstmt.setString(2, username);
                        pstmt.setString(3, configName);
                        pstmt.addBatch();
                    }
                    
                    pstmt.executeBatch();
                    connection.commit();
                    pstmt.close();
                    
                    return true;
                } catch (Exception e) {
                    e.printStackTrace();
                    try {
                        connection.rollback();
                    } catch (SQLException ex) {
                        ex.printStackTrace();
                    }
                    return false;
                } finally {
                    try {
                        connection.setAutoCommit(true);
                    } catch (SQLException e) {
                        e.printStackTrace();
                    }
                }
            }
            
            @Override
            protected void done() {
                try {
                    boolean success = get();
                    if (success) {
                        JOptionPane.showMessageDialog(OracleDataCleanup.this, 
                                "配置已成功保存", "保存成功", JOptionPane.INFORMATION_MESSAGE);
                    } else {
                        JOptionPane.showMessageDialog(OracleDataCleanup.this, 
                                "保存配置时发生错误", "保存错误", JOptionPane.ERROR_MESSAGE);
                    }
                } catch (Exception e) {
                    e.printStackTrace();
                    JOptionPane.showMessageDialog(OracleDataCleanup.this, 
                            "保存配置时发生错误: " + e.getMessage(), "保存错误", JOptionPane.ERROR_MESSAGE);
                }
            }
        };
        
        worker.execute();
    }
    
    /**
     * 批准选中的候选
     */
    private void approveSelectedCandidates() {
        if (connection == null) return;
        
        int[] selectedRows = candidatesTable.getSelectedRows();
        if (selectedRows.length == 0) {
            JOptionPane.showMessageDialog(this, "请选择要批准的候选项", "未选择", JOptionPane.WARNING_MESSAGE);
            return;
        }
        
        final List<Integer> candidateIds = new ArrayList<>();
        for (int row : selectedRows) {
            int candidateId = (Integer) candidatesTableModel.getValueAt(row, 0);
            String status = (String) candidatesTableModel.getValueAt(row, 6);
            if ("PENDING".equals(status)) {
                candidateIds.add(candidateId);
            }
        }
        
        if (candidateIds.isEmpty()) {
            JOptionPane.showMessageDialog(this, "所选候选项中没有待处理的项", "无效选择", JOptionPane.WARNING_MESSAGE);
            return;
        }
        
        SwingWorker<Boolean, Void> worker = new SwingWorker<Boolean, Void>() {
            @Override
            protected Boolean doInBackground() throws Exception {
                try {
                    CallableStatement cstmt = connection.prepareCall("{call approve_cleanup_candidate(?)}");
                    
                    for (Integer candidateId : candidateIds) {
                        cstmt.setInt(1, candidateId);
                        cstmt.execute();
                    }
                    
                    cstmt.close();
                    return true;
                } catch (Exception e) {
                    e.printStackTrace();
                    return false;
                }
            }
            
            @Override
            protected void done() {
                try {
                    boolean success = get();
                    if (success) {
                        JOptionPane.showMessageDialog(OracleDataCleanup.this, 
                                "已批准" + candidateIds.size() + "个候选项", "批准成功", JOptionPane.INFORMATION_MESSAGE);
                        loadCandidates(); // 刷新列表
                    } else {
                        JOptionPane.showMessageDialog(OracleDataCleanup.this, 
                                "批准候选项时发生错误", "批准错误", JOptionPane.ERROR_MESSAGE);
                    }
                } catch (Exception e) {
                    e.printStackTrace();
                    JOptionPane.showMessageDialog(OracleDataCleanup.this, 
                            "批准候选项时发生错误: " + e.getMessage(), "批准错误", JOptionPane.ERROR_MESSAGE);
                }
            }
        };
        
        worker.execute();
    }
    
    /**
     * 拒绝选中的候选
     */
    private void rejectSelectedCandidates() {
        if (connection == null) return;
        
        int[] selectedRows = candidatesTable.getSelectedRows();
        if (selectedRows.length == 0) {
            JOptionPane.showMessageDialog(this, "请选择要拒绝的候选项", "未选择", JOptionPane.WARNING_MESSAGE);
            return;
        }
        
        final List<Integer> candidateIds = new ArrayList<>();
        for (int row : selectedRows) {
            int candidateId = (Integer) candidatesTableModel.getValueAt(row, 0);
            String status = (String) candidatesTableModel.getValueAt(row, 6);
            if ("PENDING".equals(status)) {
                candidateIds.add(candidateId);
            }
        }
        
        if (candidateIds.isEmpty()) {
            JOptionPane.showMessageDialog(this, "所选候选项中没有待处理的项", "无效选择", JOptionPane.WARNING_MESSAGE);
            return;
        }
        
        SwingWorker<Boolean, Void> worker = new SwingWorker<Boolean, Void>() {
            @Override
            protected Boolean doInBackground() throws Exception {
                try {
                    CallableStatement cstmt = connection.prepareCall("{call reject_cleanup_candidate(?)}");
                    
                    for (Integer candidateId : candidateIds) {
                        cstmt.setInt(1, candidateId);
                        cstmt.execute();
                    }
                    
                    cstmt.close();
                    return true;
                } catch (Exception e) {
                    e.printStackTrace();
                    return false;
                }
            }
            
            @Override
            protected void done() {
                try {
                    boolean success = get();
                    if (success) {
                        JOptionPane.showMessageDialog(OracleDataCleanup.this, 
                                "已拒绝" + candidateIds.size() + "个候选项", "拒绝成功", JOptionPane.INFORMATION_MESSAGE);
                        loadCandidates(); // 刷新列表
                    } else {
                        JOptionPane.showMessageDialog(OracleDataCleanup.this, 
                                "拒绝候选项时发生错误", "拒绝错误", JOptionPane.ERROR_MESSAGE);
                    }
                } catch (Exception e) {
                    e.printStackTrace();
                    JOptionPane.showMessageDialog(OracleDataCleanup.this, 
                            "拒绝候选项时发生错误: " + e.getMessage(), "拒绝错误", JOptionPane.ERROR_MESSAGE);
                }
            }
        };
        
        worker.execute();
    }
    
    /**
     * 执行已批准的清理
     */
    private void executeCleanup() {
        if (connection == null) return;
        
        // 确认执行
        int confirm = JOptionPane.showConfirmDialog(this, 
                "确定要执行已批准的清理操作吗？\n此操作将删除数据库中的对象，请确保已备份重要数据。", 
                "确认清理", JOptionPane.YES_NO_OPTION, JOptionPane.WARNING_MESSAGE);
        
        if (confirm != JOptionPane.YES_OPTION) {
            return;
        }
        
        // 禁用按钮，显示进度条
        executeCleanupButton.setEnabled(false);
        progressBar.setIndeterminate(true);
        progressBar.setString("正在执行清理...");
        
        SwingWorker<Boolean, Void> worker = new SwingWorker<Boolean, Void>() {
            @Override
            protected Boolean doInBackground() throws Exception {
                try {
                    CallableStatement cstmt = connection.prepareCall("{call execute_approved_cleanup}");
                    cstmt.execute();
                    cstmt.close();
                    return true;
                } catch (Exception e) {
                    e.printStackTrace();
                    return false;
                }
            }
            
            @Override
            protected void done() {
                try {
                    boolean success = get();
                    if (success) {
                        JOptionPane.showMessageDialog(OracleDataCleanup.this, 
                                "清理操作已成功执行", "清理成功", JOptionPane.INFORMATION_MESSAGE);
                        loadCandidates(); // 刷新列表
                        loadDatabaseInfo(); // 更新数据库信息
                    } else {
                        JOptionPane.showMessageDialog(OracleDataCleanup.this, 
                                "执行清理操作时发生错误", "清理错误", JOptionPane.ERROR_MESSAGE);
                    }
                } catch (Exception e) {
                    e.printStackTrace();
                    JOptionPane.showMessageDialog(OracleDataCleanup.this, 
                            "执行清理操作时发生错误: " + e.getMessage(), "清理错误", JOptionPane.ERROR_MESSAGE);
                } finally {
                    executeCleanupButton.setEnabled(true);
                    progressBar.setIndeterminate(false);
                    progressBar.setString("");
                }
            }
        };
        
        worker.execute();
    }
    
    /**
     * 运行分析
     */
    private void runAnalysis() {
        if (connection == null) return;
        
        final boolean autoApprove = autoApproveCheckbox.isSelected();
        
        // 禁用按钮，显示进度条
        runAnalysisButton.setEnabled(false);
        progressBar.setIndeterminate(true);
        progressBar.setString("正在分析数据库...");
        
        SwingWorker<Boolean, Void> worker = new SwingWorker<Boolean, Void>() {
            @Override
            protected Boolean doInBackground() throws Exception {
                try {
                    CallableStatement cstmt = connection.prepareCall("{call run_db_cleanup(?)}");
                    cstmt.setString(1, autoApprove ? "Y" : "N");
                    cstmt.execute();
                    cstmt.close();
                    return true;
                } catch (Exception e) {
                    e.printStackTrace();
                    return false;
                }
            }
            
            @Override
            protected void done() {
                try {
                    boolean success = get();
                    if (success) {
                        JOptionPane.showMessageDialog(OracleDataCleanup.this, 
                                "数据库分析已完成" + (autoApprove ? "并自动批准了清理候选" : ""), 
                                "分析成功", JOptionPane.INFORMATION_MESSAGE);
                        loadCandidates(); // 刷新列表
                        loadDatabaseInfo(); // 更新数据库信息
                        
                        // 如果有候选项，切换到候选选项卡
                        if (candidatesTableModel.getRowCount() > 0) {
                            tabbedPane.setSelectedIndex(2);
                        }
                    } else {
                        JOptionPane.showMessageDialog(OracleDataCleanup.this, 
                                "分析数据库时发生错误", "分析错误", JOptionPane.ERROR_MESSAGE);
                    }
                } catch (Exception e) {
                    e.printStackTrace();
                    JOptionPane.showMessageDialog(OracleDataCleanup.this, 
                            "分析数据库时发生错误: " + e.getMessage(), "分析错误", JOptionPane.ERROR_MESSAGE);
                } finally {
                    runAnalysisButton.setEnabled(true);
                    progressBar.setIndeterminate(false);
                    progressBar.setString("");
                }
            }
        };
        
        worker.execute();
    }
    
    /**
     * 生成报告
     */
    private void generateReport() {
        if (connection == null) return;
        
        final int daysBack = (Integer) daysBackSpinner.getValue();
        
        // 禁用按钮
        generateReportButton.setEnabled(false);
        reportTextArea.setText("正在生成报告...");
        
        SwingWorker<String, Void> worker = new SwingWorker<String, Void>() {
            @Override
            protected String doInBackground() throws Exception {
                StringBuilder report = new StringBuilder();
                try {
                    // 创建一个特殊的连接来捕获DBMS_OUTPUT
                    Connection conn = DriverManager.getConnection(jdbcUrl, username, password);
                    
                    // 启用DBMS_OUTPUT
                    CallableStatement enableStmt = conn.prepareCall("BEGIN DBMS_OUTPUT.ENABLE(NULL); END;");
                    enableStmt.execute();
                    enableStmt.close();
                    
                    // 调用报告存储过程
                    CallableStatement reportStmt = conn.prepareCall("{call show_cleanup_report(?)}");
                    reportStmt.setInt(1, daysBack);
                    reportStmt.execute();
                    reportStmt.close();
                    
                    // 获取DBMS_OUTPUT的内容
                    CallableStatement getLineStmt = conn.prepareCall(
                            "BEGIN DBMS_OUTPUT.GET_LINE(:line, :status); END;");
                    getLineStmt.registerOutParameter(1, Types.VARCHAR);
                    getLineStmt.registerOutParameter(2, Types.INTEGER);
                    
                    String line;
                    int status;
                    do {
                        getLineStmt.execute();
                        line = getLineStmt.getString(1);
                        status = getLineStmt.getInt(2);
                        
                        if (status == 0 && line != null) {
                            report.append(line).append("\n");
                        }
                    } while (status == 0);
                    
                    getLineStmt.close();
                    conn.close();
                    
                    return report.toString();
                } catch (Exception e) {
                    e.printStackTrace();
                    return "生成报告时发生错误: " + e.getMessage();
                }
            }
            
            @Override
            protected void done() {
                try {
                    String reportText = get();
                    reportTextArea.setText(reportText);
                    reportTextArea.setCaretPosition(0); // 滚动到顶部
                } catch (Exception e) {
                    e.printStackTrace();
                    reportTextArea.setText("生成报告时发生错误: " + e.getMessage());
                } finally {
                    generateReportButton.setEnabled(true);
                }
            }
        };
        
        worker.execute();
    }
    
    /**
     * 主方法
     */
    public static void main(String[] args) {
        SwingUtilities.invokeLater(new Runnable() {
            @Override
            public void run() {
                new OracleDataCleanup().setVisible(true);
            }
        });
    }
}