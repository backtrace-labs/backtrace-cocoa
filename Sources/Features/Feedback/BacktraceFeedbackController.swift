#if os(iOS) && !targetEnvironment(macCatalyst)
import UIKit
import Foundation

/// Completion handler for feedback submission.
public typealias FeedbackCompletion = (_ success: Bool) -> Void

/// A view controller presenting an in-app feedback form with screenshot preview, text input,
/// and optional email field. Submits feedback as a Backtrace report.
@objc public class BacktraceFeedbackController: UIViewController {

    // MARK: - UI Elements

    private lazy var screenshotImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.layer.borderColor = UIColor.systemGray4.cgColor
        iv.layer.borderWidth = 1
        iv.layer.cornerRadius = 8
        iv.clipsToBounds = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private lazy var feedbackTextView: UITextView = {
        let tv = UITextView()
        tv.font = .systemFont(ofSize: 16)
        tv.layer.borderColor = UIColor.systemGray4.cgColor
        tv.layer.borderWidth = 1
        tv.layer.cornerRadius = 8
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    private lazy var emailTextField: UITextField = {
        let tf = UITextField()
        tf.placeholder = "Email (optional)"
        tf.keyboardType = .emailAddress
        tf.autocapitalizationType = .none
        tf.borderStyle = .roundedRect
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()

    private lazy var submitButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("Submit Feedback", for: .normal)
        btn.titleLabel?.font = .boldSystemFont(ofSize: 17)
        btn.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private lazy var cancelButton: UIBarButtonItem = {
        UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
    }()

    // MARK: - Properties

    private let screenshot: UIImage?
    private let settings: BacktraceFeedbackSettings
    private let onSubmit: (_ feedbackText: String, _ email: String?, _ screenshot: UIImage?) -> Void
    private let onCancel: () -> Void

    // MARK: - Init

    init(screenshot: UIImage?,
         settings: BacktraceFeedbackSettings,
         onSubmit: @escaping (_ feedbackText: String, _ email: String?, _ screenshot: UIImage?) -> Void,
         onCancel: @escaping () -> Void) {
        self.screenshot = screenshot
        self.settings = settings
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "Send Feedback"
        navigationItem.leftBarButtonItem = cancelButton
        view.backgroundColor = .systemBackground
        setupLayout()
        screenshotImageView.image = screenshot
    }

    // MARK: - Layout

    private func setupLayout() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let stack = UIStackView(arrangedSubviews: [screenshotImageView, feedbackTextView])
        if settings.emailFieldVisible {
            stack.addArrangedSubview(emailTextField)
            if settings.emailMandatory {
                emailTextField.placeholder = "Email (required)"
            }
        }
        stack.addArrangedSubview(submitButton)
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -16),

            screenshotImageView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.3),
            feedbackTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
            emailTextField.heightAnchor.constraint(equalToConstant: 44),
            submitButton.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    // MARK: - Actions

    @objc private func submitTapped() {
        let text = feedbackTextView.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            feedbackTextView.layer.borderColor = UIColor.systemRed.cgColor
            return
        }

        if settings.emailMandatory {
            let email = emailTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !email.isEmpty else {
                emailTextField.layer.borderColor = UIColor.systemRed.cgColor
                return
            }
        }

        let email = emailTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        dismiss(animated: true) { [weak self] in
            self?.onSubmit(text, email, self?.screenshot)
        }
    }

    @objc private func cancelTapped() {
        dismiss(animated: true) { [weak self] in
            self?.onCancel()
        }
    }
}
#endif
