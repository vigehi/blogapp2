

DECLARE
		v_org_id			integer;
	v_period_id			integer;
	msg					varchar(120);
	v_recorded_by       integer;
	    rec4        RECORD;
    rec2        RECORD;
    rec3        RECORD;
    v_member_id    integer;
    v_entity_id    integer;
	rec5			RECORD;
	   v_calculate_penalty    boolean;
BEGIN

	IF ($3 = '1') THEN
		DELETE FROM account_activity WHERE period_id = $1::int AND activity_type_id= 9;
		UPDATE periods SET opened = true, closed = false WHERE period_id = $1::int;
		UPDATE year_weeks SET week_open = true WHERE period_id = $1::int;
		msg := 'Period/Month Opened';
	ELSIF ($3 = '2') THEN
			UPDATE periods SET entity_id = $2::INT, approve_status = 'Pending' WHERE period_id = $1::int;
		UPDATE year_weeks SET week_closed = true, week_open = false WHERE period_id = $1::int;
		msg := 'Period/Month submitted for approval';

	ELSIF ($3 = '3') THEN
		UPDATE periods SET activated = true WHERE period_id = $1::int;
		UPDATE year_weeks SET week_active = true WHERE period_id = $1::int;
		msg := 'Period/Month Activated';
	ELSIF ($3 = '4') THEN
		UPDATE periods SET activated = false WHERE period_id = $1::int;
		UPDATE year_weeks SET week_active = false WHERE period_id = $1::int;
		msg := 'Period/Month De-activated';
	ELSIF ($3 = '5') THEN
		---activate and open periods/months
		UPDATE periods SET opened = true, activated = true WHERE period_id = $1::int;
		---activate and open weeks
		UPDATE year_weeks SET week_open = true, week_active = true WHERE period_id = $1::int;
		msg := 'Period/Month Opened and Activated Successfully..';
	ELSIF ($3 = '6') THEN
		SELECT entity_id INTO v_recorded_by FROM periods WHERE period_id = $1::int and  approve_status = 'Pending' ;
		SELECT calculate_penalty INTO v_calculate_penalty FROM periods WHERE period_id = $1::int;
			IF(v_recorded_by = $2::int)THEN 
				RAISE EXCEPTION 'Period Approval Denied...!';
			ElSIF (v_recorded_by is null) THEN
			RAISE EXCEPTION 'Not submitted for approval..!';
			ELSEIF (v_calculate_penalty = true) THEN
		-- UPDATE periods SET closed = true, opened = false, period_closed_by = $2::INT,  approve_status = 'Approved' WHERE period_id = $1::int;
		------------------------Compute Penalty--------------------------
		UPDATE loan_schedule SET penalty_amount = 0;
		UPDATE loan_schedule SET penalty_amount = vw_loan_schedule.repayment_amount * (vw_loan_schedule.penalty_rate * 0.01) --vw_loan_schedule.pending_amount * 0.1
		FROM vw_loan_schedule INNER JOIN periods ON periods.org_id = vw_loan_schedule.org_id
		WHERE (loan_schedule.loan_schedule_id = vw_loan_schedule.loan_schedule_id)
			AND (vw_loan_schedule.pending_amount > 0)
			AND ((vw_loan_schedule.schedule_date) < (periods.end_date))
			AND vw_loan_schedule.schedule_date BETWEEN
			periods.start_date AND periods.end_date AND period_id = $1::int;

		------------------------Insert into loan account-------------------------------
		INSERT INTO account_activity (activity_frequency_id, activity_status_id, activity_type_id,
			org_id, loan_id, transfer_account_no, activity_date, value_date, account_credit, account_debit)
		SELECT 1, 1, 9, 0, ls.loan_id, '400000005',
			ls.schedule_date, ls.schedule_date, 0, ls.penalty_amount
		FROM vw_loan_schedule ls LEFT JOIN vw_loan_activity aa ON
			(ls.loan_id = aa.loan_id) AND ((ls.schedule_date) = aa.value_date) AND
			(aa.activity_type_id = 9)
		WHERE (ls.penalty_amount > 0)
			AND (ls.product_id IN (3, 4, 5)) AND (aa.account_activity_id is null);
			
			-----------------------------------------Jamii--------------------------------------
			select  start_date, end_date into rec3 from periods where period_id = $1::int;
				SELECT has_penalty, penalty_amount INTO rec2  FROM contribution_definations
				WHERE activity_type_id  = 39 and is_active = 'true';

				SELECT value_date INTO rec5 FROM vw_deposit_payment_details
				WHERE activity_type_id  = 39;

				IF (rec2.has_penalty = 'true') AND (rec5.value_date BETWEEN rec3.start_date::DATE AND rec3.end_date::DATE ) THEN
						

						SELECT * INTO rec4 FROM member_contribution_configs
						WHERE activity_type_id  = 39 AND ( member_id NOT IN (SELECT member_id FROM vw_deposit_payment_details));

						INSERT INTO transactions( transaction_type_id, transaction_status_id, bank_account_id,
							 currency_id, department_id, entered_by, org_id, exchange_rate, transaction_date, payment_date,
							transaction_amount, member_id, activity_type_id, activity_frequency_name)
							SELECT  10, 4,0,1,0, 0,0,1, rec3.start_date::DATE, rec3.end_date::DATE,rec2.penalty_amount, member_id,39,'Monthly'
									FROM  member_contribution_configs
									WHERE activity_type_id  = 39 AND member_id NOT IN (SELECT member_id FROM vw_deposit_payment_details
																					 where period_id= $1::int);

				END IF;
			

		------------------------Close period-------------------------------
		UPDATE periods SET closed = true, opened = false, period_closed_by = $2::INT,  approve_status = 'Approved' WHERE period_id = $1::int;
		UPDATE year_weeks SET week_closed = true, week_open = false, week_active = false WHERE period_id = $1::int;
	
		msg := 'Period Approved Successfully.....';
		ELSE
		UPDATE periods SET closed = true, opened = false, period_closed_by = $2::INT,  approve_status = 'Approved' WHERE period_id = $1::int;
		UPDATE year_weeks SET week_closed = true, week_open = false, week_active = false WHERE period_id = $1::int;
-- 		msg := 'Period/Month Closed';
				msg := 'Period Approved Successfully.....';
			END IF;
		END IF;
	RETURN msg;
END;

